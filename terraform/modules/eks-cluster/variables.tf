variable "project_name" {
  description = "Project name for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for EKS."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS control plane and Fargate."
  type        = list(string)
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API endpoint."
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (OIDC provider)."
  type        = bool
  default     = true
}

variable "create_fargate_profile_for_karpenter" {
  description = "Create Fargate profile for Karpenter namespace."
  type        = bool
  default     = true
}

variable "karpenter_namespace" {
  description = "Namespace used by Karpenter (for Fargate profile selector)."
  type        = string
  default     = "karpenter"
}

variable "create_fargate_profile_for_kube_system" {
  description = "Create Fargate profile only for CoreDNS (selector: kube-system + label k8s-app=kube-dns). Não cria profile para kube-system inteiro."
  type        = bool
  default     = false
}

variable "create_ebs_kms_key" {
  description = "Create EBS KMS key for volume encryption (if not using existing)."
  type        = bool
  default     = false
}

variable "enable_managed_node_group" {
  description = "Create an initial managed node group for system add-ons (CoreDNS, etc.). Com Karpenter, normalmente false (nodes sob demanda)."
  type        = bool
  default     = false
}

variable "node_group_instance_types" {
  description = "Instance types for the initial managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Desired size for the initial managed node group."
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Min size for the initial managed node group."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Max size for the initial managed node group."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags for resources."
  type        = map(string)
  default     = {}
}

variable "cluster_endpoint_public_access_cidrs" {
  type = list(string)
}
