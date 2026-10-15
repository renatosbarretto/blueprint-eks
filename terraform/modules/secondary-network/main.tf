# -----------------------------------------------------------------------------
# Secondary CIDR block for VPC (e.g. 10.147.0.0/16)
# Provides additional IP space and optional routing to primary CIDR
# -----------------------------------------------------------------------------
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = var.vpc_id
  cidr_block = var.secondary_cidr
}

# -----------------------------------------------------------------------------
# Subnets for secondary CIDR (optional: one subnet per AZ)
# -----------------------------------------------------------------------------
locals {
  # Split secondary CIDR into /20 or similar for subnets; here we use one /20 per AZ for simplicity
  # For 10.147.0.0/16 we could use 10.147.0.0/20, 10.147.16.0/20, 10.147.32.0/20
  secondary_subnet_cidrs = length(var.secondary_subnet_cidrs) > 0 ? var.secondary_subnet_cidrs : [
    for i in range(length(var.availability_zones)) : cidrsubnet(var.secondary_cidr, 4, i)
  ]
}

resource "aws_subnet" "secondary" {
  count = var.create_secondary_subnets ? length(var.availability_zones) : 0

  vpc_id            = var.vpc_id
  cidr_block        = local.secondary_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-secondary-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

# -----------------------------------------------------------------------------
# Route table for secondary CIDR (route to primary VPC via local)
# Routing 10.147.x -> 10.0.x is implicit (same VPC) once secondary CIDR is attached
# -----------------------------------------------------------------------------
resource "aws_route_table" "secondary" {
  count = var.create_secondary_subnets ? 1 : 0

  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-secondary-rt"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

resource "aws_route_table_association" "secondary" {
  count = var.create_secondary_subnets ? length(aws_subnet.secondary) : 0

  subnet_id      = aws_subnet.secondary[count.index].id
  route_table_id = aws_route_table.secondary[0].id
}
