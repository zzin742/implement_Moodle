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
  description = "EC2 instance type for Moodle"
  type        = string
  default     = "t3.medium"
}

variable "ec2_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  sensitive   = true
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into EC2"
  type        = string
  default     = "0.0.0.0/0"
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
