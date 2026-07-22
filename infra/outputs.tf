output "web_public_ip" {
  description = "Public IP of the web instance."
  value       = aws_instance.web.public_ip
}

output "web_public_dns" {
  description = "Public DNS name of the web instance."
  value       = aws_instance.web.public_dns
}

output "web_url" {
  description = "Open this in a browser (or curl it) once apply finishes -- give it ~30-60s for user_data to finish installing nginx."
  value       = "http://${aws_instance.web.public_ip}"
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
