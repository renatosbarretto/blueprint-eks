variable "cluster_name" { type = string }
variable "domain_name" { type = string }
variable "route53_hosted_zone_id" { type = string }
variable "environment" { type = string }
variable "region" { type = string }
variable "chart_version" { type = string }

variable "route53_assume_role_arn" {
  description = "Role na conta da zona (cross-account). Vazio = zona na mesma conta."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
