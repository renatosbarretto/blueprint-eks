variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint."
  type        = string
}

variable "cluster_certificate" {
  description = "EKS cluster CA certificate."
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for ALB controller."
  type        = string
}

variable "region" {
  description = "AWS region (for update-kubeconfig in CRD install)."
  type        = string
  default     = "us-east-1"
}

variable "gateway_api_version" {
  description = "Gateway API CRDs Helm chart version (e.g. 1.0.0)."
  type        = string
  default     = "1.2.0"
}

variable "tags" {
  description = "Tags for AWS resources."
  type        = map(string)
  default     = {}
}

variable "helm_values" {
  type    = list(string)
  default = []
}
