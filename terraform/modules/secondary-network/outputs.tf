output "secondary_cidr_association_id" {
  description = "Secondary CIDR block association ID."
  value       = aws_vpc_ipv4_cidr_block_association.secondary.id
}

output "secondary_cidr_block" {
  description = "Secondary CIDR block."
  value       = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
}

output "secondary_subnet_ids" {
  description = "Secondary subnet IDs (when create_secondary_subnets = true)."
  value       = var.create_secondary_subnets ? aws_subnet.secondary[*].id : []
}

output "secondary_route_table_id" {
  description = "Route table ID for secondary subnets (when created)."
  value       = var.create_secondary_subnets ? aws_route_table.secondary[0].id : null
}
