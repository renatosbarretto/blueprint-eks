variable "account_id" {
  description = "Conta AWS alvo (vem do account.yaml)."
  type        = string
}

variable "region" {
  description = "Região do provider (IAM é global)."
  type        = string
}

variable "github_repository" {
  description = "Repositório owner/nome autorizado a assumir as roles."
  type        = string
  default     = "renatosbarretto/blueprint-eks"
}

variable "state_bucket" {
  description = "Bucket de state do Terragrunt (eks-blueprint-tfstate-<conta>)."
  type        = string
}

variable "create_oidc_provider" {
  description = "false quando a conta já tem o provider token.actions.githubusercontent.com (o script detecta)."
  type        = bool
  default     = true
}

variable "apply_max_session_seconds" {
  description = "Duração máxima da sessão de apply (apply completo de um cluster passa de 1h)."
  type        = number
  default     = 7200
}
