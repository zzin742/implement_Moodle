# TODO: Adicionar output para security group caso seja necessário acesso de outras fontes

output "rds_endpoint" {
  description = "Connection endpoint for RDS (hostname:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Port for RDS PostgreSQL"
  value       = aws_db_instance.main.port
}
