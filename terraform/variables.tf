# TODO: Considerar uso de AWS Secrets Manager para db_password em produção

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "moodle-challenge"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ec2_instance_type" {
  description = <<-TXT
    Tipo da instância EC2.

    O default é t3.micro, que é o que o enunciado da prova pede. Vale registrar
    uma medição que contraria esse valor: o user_data constrói a imagem Docker
    na própria instância, compilando nove extensões PHP, e esse build consumiu
    bem mais que 1 GB de RAM. No apply real deste projeto a instância usada foi
    t3.medium (2 vCPU, 4 GB) e o Moodle subiu em cerca de cinco minutos.

    Com t3.micro o passo do `gd` é o candidato a ser morto por OOM, e o sintoma
    engana: o `terraform apply` termina verde, a instância sobe, e só o
    /var/log/user-data.log mostra o build interrompido.

    Por isso é variável, e não constante: quem for aplicar pode subir para
    t3.medium sem tocar no código.
  TXT
  type        = string
  default     = "t3.micro"
}

variable "ec2_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  sensitive   = true
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into EC2"
  type        = string
  # Marcada como sensitive porque contém dado pessoal (não é segredo criptográfico):
  # o IP residencial/corporativo do operador com /32 revela o endereço de onde ele trabalha.
  # Em repositório público, esse valor apareceria no GITHUB_STEP_SUMMARY do terraform plan.
  sensitive = true

  validation {
    condition     = var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "SSH access from 0.0.0.0/0 (internet inteira) é proibido por segurança. Especifique seu IP público (ex: \"203.0.113.45/32\"). Descubra seu IP com: curl -s https://checkip.amazonaws.com"
  }
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master password for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "moodle"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "repo_url" {
  description = "Git repository URL to clone for Moodle application"
  type        = string
  default     = "https://github.com/zzin742/implement_Moodle.git"
}

variable "moodle_admin_user" {
  description = "Moodle administrator username"
  type        = string
  default     = "admin"
}

variable "moodle_admin_password" {
  description = "Moodle administrator password"
  type        = string
  sensitive   = true
}

variable "moodle_site_name" {
  description = "Moodle site name"
  type        = string
  default     = "Moodle Challenge"
}

# Alteracao minima em terraform/** para o workflow Terraform Plan disparar
# nesta PR e publicar o plano como comentario, que e o comportamento que o
# enunciado da prova pede verificar.
