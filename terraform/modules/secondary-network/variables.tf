variable "vpc_id" {
  description = "VPC ID to attach secondary CIDR."
  type        = string
}

variable "secondary_cidr" {
  description = "Secondary CIDR block (e.g. 10.147.0.0/16)."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for secondary subnets."
  type        = list(string)
}

variable "project_name" {
  description = "Project name for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "create_secondary_subnets" {
  description = "Create subnets in secondary CIDR."
  type        = bool
  default     = true
}

variable "secondary_subnet_cidrs" {
  description = "Optional list of CIDRs for secondary subnets (one per AZ)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for resources."
  type        = map(string)
  default     = {}
}
