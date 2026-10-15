# -----------------------------------------------------------------------------
# GitHub Actions OIDC — variáveis
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organization or user (owner of the repo)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "role_name" {
  description = "IAM role name for GitHub Actions."
  type        = string
  default     = "github-actions-oidc"
}

variable "allow_environment" {
  description = "Protected GitHub environment allowed to assume this role."
  type        = string
  validation {
    condition     = length(var.allow_environment) > 0 && !strcontains(var.allow_environment, "*")
    error_message = "Specify an exact environment name."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if it already exists in the account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for the IAM role."
  type        = map(string)
  default     = {}
}

variable "deploy_policy_arns" {
  type        = set(string)
  description = "Existing managed policies reviewed for this account, stack and backend."
  validation {
    condition     = length(var.deploy_policy_arns) > 0
    error_message = "Provide explicit deploy policy ARNs; no permissions are granted implicitly."
  }
}
