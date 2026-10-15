output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "NAT gateway public IPs (one per AZ when NAT enabled)."
  value       = var.enable_nat_gateway ? aws_eip.nat[*].public_ip : []
}

output "internet_gateway_id" {
  description = "Internet gateway ID."
  value       = aws_internet_gateway.main.id
}
