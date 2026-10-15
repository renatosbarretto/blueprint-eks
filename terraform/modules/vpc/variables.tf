variable "project_name" {
  description = "Project name for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway(s) for private subnets."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use um único NAT Gateway na primeira AZ (mais barato). Se false, um NAT por AZ (maior disponibilidade)."
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Attach VPN gateway (placeholder for future)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention in days for flow logs."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
