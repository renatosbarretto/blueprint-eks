variable "cluster_name" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "chart_version" { type = string }

variable "tenants" {
  description = "Tenants do cartão: cada um ganha role IAM + ClusterSecretStore tenant-<name> restrito aos seus namespaces."
  type = list(object({
    name       = string
    namespaces = list(string)
  }))
  default = []
}

variable "platform_namespaces" {
  description = "Namespaces que podem usar o ClusterSecretStore platform (<cluster>/platform/*)."
  type        = list(string)
  default     = ["external-secrets", "external-dns", "gateway-api-system", "argocd", "karpenter"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
