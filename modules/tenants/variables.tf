variable "cluster_name" { type = string }
variable "region" { type = string }

variable "tenants" {
  type = list(object({
    name       = string
    namespaces = list(string)
  }))
  default = []

  validation {
    condition     = length(flatten([for t in var.tenants : t.namespaces])) == length(distinct(flatten([for t in var.tenants : t.namespaces])))
    error_message = "Um namespace não pode pertencer a dois tenants."
  }
}

variable "pod_security_enforce" {
  type    = string
  default = "baseline"

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_enforce)
    error_message = "pod_security_enforce deve ser privileged, baseline ou restricted."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
