variable "cluster_name" {
  description = "EKS cluster name (for dependency)."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint (for dependency)."
  type        = string
}

variable "cluster_certificate" {
  description = "EKS cluster CA certificate (for dependency)."
  type        = string
  sensitive   = true
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD."
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version (e.g. 6.0.0)."
  type        = string
  default     = "6.0.0"
}

variable "helm_values" {
  description = "Additional Helm values for ArgoCD."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags (for consistency; Helm release may not support)."
  type        = map(string)
  default     = {}
}
