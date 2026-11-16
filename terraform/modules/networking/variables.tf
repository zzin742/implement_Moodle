# TODO: Considerar parametrização dos CIDRs das subnets para maior flexibilidade

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
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
