# TODO: Adicionar filtro por architecture para suportar ARM (Graviton) no futuro

# Data source: AMI Amazon Linux 2023 mais recente
# NUNCA usar AMI ID fixo - IDs são regionais e AWS publica novas versões
# Após algumas semanas, AMI antiga é removida e ID fixo causa InvalidAMIID.NotFound
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source: IAM Instance Profile do AWS Learn Lab
# CRÍTICO: AWS Learn Lab PROÍBE criar recursos IAM (iam_role, iam_instance_profile, etc)
# Tentar criar resource IAM causa AccessDenied após VPC/RDS já criados (órfãos custando crédito)
# LabInstanceProfile já existe na conta - referenciar via data source
data "aws_iam_instance_profile" "lab_role" {
  name = "LabInstanceProfile"
}

# Key pair para acesso SSH
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.ec2_public_key

  tags = {
    Name = "${var.project_name}-key"
  }
}

# TODO: Avaliar uso de Launch Template + Auto Scaling Group para produção

# Instância EC2 rodando Moodle via Docker
resource "aws_instance" "moodle" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type

  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.ec2_security_group_id]

  key_name             = aws_key_pair.main.key_name
  iam_instance_profile = data.aws_iam_instance_profile.lab_role.name

  # Disco raiz: 30 GB necessários para Docker images + Moodle
  # Os 8 GB padrão causam erro "no space left on device" durante build
  # Breakdown: imagem base (~2GB) + camadas intermediárias (~3GB) + Moodle (~500MB) + dados
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 obrigatório - protege contra SSRF
  # Com IMDSv1 ativo, um SSRF na aplicação pode ler credenciais da instance profile
  # IMDSv2 exige header HTTP adicional, bloqueando ataques simples de SSRF
  metadata_options {
    http_tokens                 = "required" # Force IMDSv2
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  # User data para inicialização - renderizado via templatefile()
  # Variáveis Terraform (sem $): ${rds_endpoint}, ${db_name}, etc
  # Variáveis shell (com $$): $${VARIABLE} - escapadas para não serem interpretadas pelo Terraform
  user_data = templatefile("${path.module}/user_data.sh", {
    rds_endpoint          = var.rds_endpoint
    db_name               = var.db_name
    db_username           = var.db_username
    db_password           = var.db_password
    project_name          = var.project_name
    repo_url              = var.repo_url
    moodle_admin_user     = var.moodle_admin_user
    moodle_admin_password = var.moodle_admin_password
    moodle_site_name      = var.moodle_site_name
  })

  # CRÍTICO: força recriação da instância se user_data mudar
  # Sem isso, alterar o script só vale para instância nova
  # Apply responde "No changes" enquanto instância continua com versão antiga
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-ec2"
  }
}
