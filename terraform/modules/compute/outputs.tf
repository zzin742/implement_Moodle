# TODO: Adicionar output com private IP para troubleshooting de rede interna

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.moodle.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.moodle.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.moodle.public_dns
}

output "ec2_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.moodle.private_ip
}
