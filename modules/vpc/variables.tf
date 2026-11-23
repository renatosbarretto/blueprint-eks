variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  description = "EKS cluster name used in kubernetes.io/cluster/* and karpenter.sh/discovery subnet tags."
  type        = string
}

variable "vpc_cidr" {
  type = string

  validation {
    condition = (
      can(cidrhost(var.vpc_cidr, 0)) &&
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 18
    )
    error_message = "vpc_cidr deve ser /16 a /18 (privadas /19 a /21 por AZ)."
  }
}

variable "availability_zones" {
  type = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 7
    error_message = "Use de 2 a 7 AZs (o layout reserva um bloco /19 para as públicas)."
  }
}

variable "nat_gateway_mode" {
  description = "single = 1 NAT (barato, egress cai se a AZ cair); per_az = 1 NAT por AZ."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode deve ser single ou per_az."
  }
}

variable "interface_endpoints" {
  description = "Serviços para interface endpoints (ex: ecr.api, ecr.dkr, sts, ec2, sqs, logs)."
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  type    = bool
  default = false
}

variable "flow_logs_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
