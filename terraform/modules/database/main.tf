# TODO: Implementar Multi-AZ e automated backups para produção

# DB Subnet Group - agrupa as subnets privadas onde o RDS pode ser provisionado
# Exige mínimo de 2 AZs diferentes (por isso temos private_1a e private_1b)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# RDS PostgreSQL 15 - banco de dados gerenciado
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  # Engine configuration
  engine = "postgres"
  # IMPORTANTE: usar apenas major version (15), não minor (15.x)
  # AWS deprecia versões minor antigas e apply falha com InvalidParameterValue
  # Com "15", AWS usa a minor mais recente disponível automaticamente
  engine_version = "15"

  # Instance configuration
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  # CRÍTICO: publicly_accessible = false
  # RDS não deve ser acessível da internet, apenas da VPC (via EC2)
  publicly_accessible = false

  # Availability configuration
  # TODO: Habilitar Multi-AZ em produção para alta disponibilidade
  multi_az = false

  # Backup configuration
  # TODO: Configurar retenção de backups em produção (ex: 7 dias)
  backup_retention_period = 0
  # TODO: Remover skip_final_snapshot em produção - sempre criar snapshot final
  skip_final_snapshot = true

  # Maintenance
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-rds"
  }
}
