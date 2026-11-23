variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "namespace" {
  type    = string
  default = "karpenter"
}

variable "karpenter_version" {
  type = string
}

variable "replicas" {
  type    = number
  default = 1
}

variable "ami_alias" {
  description = "Alias do EC2NodeClass (ex: al2023@v20261119). Fixe a versão fora de dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+@(latest|v[0-9]{8})$", var.ami_alias))
    error_message = "ami_alias deve ser <familia>@latest ou <familia>@vYYYYMMDD."
  }
}

variable "arch" {
  type    = list(string)
  default = ["amd64"]
}

variable "capacity_types" {
  type    = list(string)
  default = ["spot", "on-demand"]
}

variable "limits" {
  description = "Limites do NodePool default (cpu, memory)."
  type        = map(string)
}

variable "root_volume_size_gib" {
  type    = number
  default = 40
}

variable "region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
