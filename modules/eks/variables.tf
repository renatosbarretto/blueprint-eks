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
  description = "Explicit EKS cluster name."
  type        = string
}

variable "cluster_version" {
  type = string
}

variable "support_type" {
  description = "STANDARD evita entrar automaticamente em extended support (cobrança ~6x)."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type deve ser STANDARD ou EXTENDED."
  }
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "api_public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint público. Lista vazia = endpoint só privado."
  type        = list(string)
  default     = []
}

variable "cluster_log_retention_days" {
  type    = number
  default = 30
}

variable "access_entries" {
  description = <<-EOT
    EKS Access Entries. Informe principal_arn (com account_id já expandido pelo root.hcl)
    OU sso_permission_set para resolver AWSReservedSSO_<set>_* na conta atual.
    namespaces vazio/ausente = escopo cluster; preenchido = escopo namespace.
  EOT
  type = list(object({
    name               = string
    policy_arn         = string
    principal_arn      = optional(string)
    sso_permission_set = optional(string)
    namespaces         = optional(list(string))
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.access_entries :
      (try(e.principal_arn, null) != null && e.principal_arn != "") ||
      (try(e.sso_permission_set, null) != null && e.sso_permission_set != "")
    ])
    error_message = "Cada access_entry precisa de principal_arn ou sso_permission_set."
  }
}

variable "enable_breakglass_role" {
  type    = bool
  default = true
}

variable "eks_addon_versions" {
  description = "Override de versão por addon (nome do addon → versão). Ausente = default da AWS para a cluster_version."
  type        = map(string)
  default     = {}
}

variable "enable_network_policy" {
  type    = bool
  default = true
}

variable "karpenter_namespace" {
  type    = string
  default = "karpenter"
}

variable "tags" {
  type    = map(string)
  default = {}
}
