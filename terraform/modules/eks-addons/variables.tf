variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint (for provider dependency)."
  type        = string
}

variable "cluster_certificate_data" {
  description = "EKS cluster CA certificate (base64)."
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

variable "enable_vpc_cni" {
  description = "Enable VPC CNI add-on."
  type        = bool
  default     = true
}

variable "enable_vpc_cni_custom_networking" {
  description = "Ativa custom networking no VPC CNI via configuration_values do add-on (rede secundária, ex.: 10.147). Define AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG e ENI_CONFIG_LABEL_DEF."
  type        = bool
  default     = false
}

variable "enable_coredns" {
  description = "Enable CoreDNS add-on."
  type        = bool
  default     = true
}

variable "coredns_compute_type_fargate" {
  description = "Configura o add-on CoreDNS para Fargate (configuration_values computeType = Fargate). Use quando o CoreDNS rodar no Fargate."
  type        = bool
  default     = false
}

variable "enable_kube_proxy" {
  description = "Enable kube-proxy add-on."
  type        = bool
  default     = true
}

variable "enable_ebs_csi" {
  description = "Enable EBS CSI driver add-on."
  type        = bool
  default     = true
}

variable "enable_efs_csi" {
  description = "Enable EFS CSI driver add-on."
  type        = bool
  default     = false
}

variable "enable_metrics_server" {
  description = "Enable metrics-server via Helm."
  type        = bool
  default     = true
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS volume encryption (optional)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for resources."
  type        = map(string)
  default     = {}
}

variable "enable_ebs_kms_policy" {
  type    = bool
  default = false
}
