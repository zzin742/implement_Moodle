# TODO: Adicionar output com URL completa do Moodle para facilitar acesso após deploy

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "ec2_public_dns" {
  description = "Public DNS name of the EC2 instance running Moodle"
  value       = module.compute.ec2_public_dns
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.compute.ec2_instance_id
}

output "rds_endpoint" {
  description = "Connection endpoint for RDS PostgreSQL"
  value       = module.database.rds_endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Port for RDS PostgreSQL"
  value       = module.database.rds_port
}

output "moodle_url" {
  description = "URL to access Moodle (HTTP only - AWS Learn Lab limitation)"
  value       = "http://${module.compute.ec2_public_dns}"
}
