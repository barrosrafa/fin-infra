output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block da VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas de computação (ECS)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs das subnets privadas isoladas de banco e cache (Redis)"
  value       = aws_subnet.database[*].id
}

output "nat_gateway_ips" {
  description = "IPs estáticos públicos de saída (Egress IPs dos NAT Gateways)"
  value       = aws_eip.nat[*].public_ip
}
