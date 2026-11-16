# TODO: Parametrizar tamanho do disco raiz para permitir ajustes sem recriar instância

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ec2_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  sensitive   = true
}

variable "public_subnet_id" {
  description = "ID of public subnet for EC2"
  type        = string
}

variable "ec2_security_group_id" {
  description = "Security group ID for EC2"
  type        = string
}

variable "rds_address" {
  description = "RDS hostname (address only, without port) for database connection"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "repo_url" {
  description = "Git repository URL to clone for Moodle application"
  type        = string
}

variable "moodle_admin_user" {
  description = "Moodle administrator username"
  type        = string
}

variable "moodle_admin_password" {
  description = "Moodle administrator password"
  type        = string
  sensitive   = true
}

variable "moodle_site_name" {
  description = "Moodle site name"
  type        = string
}
