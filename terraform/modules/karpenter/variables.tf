variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  type        = string
}

variable "interruption_queue_name" {
  description = "SQS queue name for interruption handling (e.g. cluster name). Defaults to cluster_name."
  type        = string
  default     = null
}

variable "cluster_certificate" {
  description = "EKS cluster CA certificate (base64) - for provider dependency."
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

variable "subnet_ids" {
  description = "Private subnet IDs (for node launch - Karpenter uses these for EC2)."
  type        = list(string)
}

variable "namespace" {
  description = "Kubernetes namespace for Karpenter."
  type        = string
  default     = "karpenter"
}

variable "run_on_fargate" {
  description = "Whether Karpenter controller runs on Fargate (namespace must have Fargate profile)."
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (e.g. v0.32.0)."
  type        = string
  default     = "1.9.0"
}

variable "node_volume_type" {
  description = "EBS volume type for Karpenter-provisioned nodes."
  type        = string
  default     = "gp3"
}

variable "node_volume_size" {
  description = "EBS volume size in GB."
  type        = number
  default     = 100
}

variable "node_volume_iops" {
  description = "EBS IOPS for gp3."
  type        = number
  default     = 3000
}

variable "node_volume_throughput" {
  description = "EBS throughput in MB/s for gp3."
  type        = number
  default     = 125
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS encryption on nodes (optional)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for AWS resources."
  type        = map(string)
  default     = {}
}

variable "reserved_enis" {
  description = "Reserved ENIs for VPC CNI custom networking (set to 1 when pods use secondary CIDR). See Karpenter docs RESERVED_ENIS."
  type        = number
  default     = 0
}

variable "enable_ebs_kms_policy" {
  type    = bool
  default = false
}

variable "helm_values" {
  type    = list(string)
  default = []
}
