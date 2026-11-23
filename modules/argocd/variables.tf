variable "cluster_name" { type = string }
variable "region" { type = string }
variable "argocd_version" { type = string }

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "tags" {
  type    = map(string)
  default = {}
}
