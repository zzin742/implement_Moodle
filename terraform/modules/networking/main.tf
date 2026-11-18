# TODO: Avaliar necessidade de IPv6 em futuras iterações

# VPC principal com DNS hostnames habilitado
# DNS hostnames é CRÍTICO: sem ele, o endpoint do RDS (que é um nome DNS)
# não resolve dentro da VPC e a EC2 não consegue conectar ao banco
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Subnet pública 1, onde a EC2 roda (AZ us-east-1a)
# map_public_ip_on_launch = true garante IP público automático para instâncias
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-1a"
  }
}

# Subnet pública 2 (AZ us-east-1b)
#
# Não há nada rodando nela hoje: a EC2 é única e fica na 1a. Ela existe porque
# subnet pública numa AZ só é um ponto único de falha estrutural — qualquer
# recurso que exija alta disponibilidade (um ALB, um Auto Scaling Group) precisa
# de pelo menos duas AZs e a API recusa criar com uma. Deixar a segunda pronta
# transforma essa evolução em mudança de uma linha.
#
# É o mesmo motivo das duas subnets privadas, onde a exigência já é obrigatória
# hoje por causa do aws_db_subnet_group.
resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-1b"
  }
}

# Subnet privada 1 para RDS (AZ us-east-1a)
resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.project_name}-private-subnet-1a"
  }
}

# Subnet privada 2 para RDS (AZ us-east-1b)
# Segunda AZ é OBRIGATÓRIA: aws_db_subnet_group exige mínimo de 2 AZs
# Mesmo sem instância RDS rodando na segunda AZ, o subnet group precisa dela
resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "${var.project_name}-private-subnet-1b"
  }
}

# Internet Gateway para acesso externo
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table pública com rota para internet via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associação da route table pública à subnet pública
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# A segunda subnet pública precisa da MESMA route table. Sem esta associação ela
# herdaria a route table principal da VPC, que só tem a rota local — seria uma
# subnet "pública" sem saída para a internet, e o erro só apareceria no dia em
# que algo fosse lançado nela.
resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

# Security Group para EC2
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for Moodle EC2 instance"
  vpc_id      = aws_vpc.main.id

  # HTTP do mundo todo (Moodle precisa ser acessível publicamente)
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH de CIDR configurável (idealmente restrito ao IP do administrador)
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Egresso liberado (EC2 precisa baixar pacotes, conectar ao RDS, etc)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# TODO: Considerar security group adicional para acesso HTTPS quando ACM estiver disponível

# Security Group para RDS - Princípio do Menor Privilégio
# Acesso PostgreSQL APENAS do security group da EC2
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL - allows access only from EC2"
  vpc_id      = aws_vpc.main.id

  # CRÍTICO: usar security_groups (referência a outro SG) ao invés de cidr_blocks
  # O IP privado da EC2 pode mudar se a instância for recriada, mas o SG permanece
  # Isso mantém a regra funcionando mesmo após recriar a instância
  ingress {
    description     = "PostgreSQL from EC2 security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# TODO: Avaliar NAT Gateway para subnets privadas em produção (custo ~$32/mês)
