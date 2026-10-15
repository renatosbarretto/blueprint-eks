# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Project name used for resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway(s) for private subnets."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use um único NAT Gateway (mais barato). Se false, um NAT por AZ (maior disponibilidade)."
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Enable VPN gateway."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_vpn_gateway
    error_message = "enable_vpn_gateway is not implemented; leave false."
  }
}

# -----------------------------------------------------------------------------
# Secondary Network
# -----------------------------------------------------------------------------
variable "secondary_cidr" {
  description = "Secondary CIDR block for VPC (e.g. 10.147.0.0/16)."
  type        = string
  default     = "10.147.0.0/16"
}

variable "enable_secondary_network" {
  description = "Enable secondary network and routing to primary VPC."
  type        = bool
  default     = false
}

variable "enable_vpc_cni_custom_networking" {
  description = "Ativa custom networking no VPC CNI (IPs dos pods na rede secundária, ex.: 10.147). Requer enable_secondary_network e subnets secundárias. Se pods falharem com 'failed to assign an IP address', defina false para usar a rede primária."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster. Use Karpenter 1.6+ for K8s 1.34."
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API endpoint (requires explicit CIDRs)."
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaling" {
  description = "Enable cluster autoscaler (legacy; prefer Karpenter)."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_cluster_autoscaling
    error_message = "enable_cluster_autoscaling is not implemented; leave false."
  }
}

variable "enable_eks_auto_mode" {
  description = "Use EKS Auto Mode (desativado por padrão). Com false, use Karpenter como provedor de compute."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_eks_auto_mode
    error_message = "enable_eks_auto_mode is not implemented; leave false."
  }
}

variable "enable_managed_node_group" {
  description = "Create initial managed node group (default: false). Com false, Karpenter provisiona nodes sob demanda."
  type        = bool
  default     = false
}

variable "node_group_desired_size" {
  description = "Desired size for initial managed node group."
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Min size for initial managed node group."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Max size for initial managed node group."
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Node Storage (EBS)
# -----------------------------------------------------------------------------
variable "node_volume_type" {
  description = "EBS volume type for nodes (e.g. gp3)."
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

variable "enable_ebs_encryption" {
  description = "Enable KMS encryption for EBS volumes."
  type        = bool
  default     = true
}

variable "ebs_kms_key_id" {
  description = "KMS key ARN for EBS encryption."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Karpenter
# -----------------------------------------------------------------------------
variable "enable_karpenter" {
  description = "Karpenter como único provedor de compute (nodes sob demanda)."
  type        = bool
  default     = true
}

variable "karpenter_ami_alias" {
  description = "AMI alias para EC2NodeClass (ex.: al2023@latest ou al2023@v20240703). Em produção prefira versão fixa."
  type        = string
  default     = "al2023@latest"
}

variable "karpenter_namespace" {
  description = "Namespace for Karpenter."
  type        = string
  default     = "karpenter"
}

variable "karpenter_on_fargate" {
  description = "Run Karpenter on Fargate."
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (sem prefixo 'v'). Use 1.6+ para Kubernetes 1.34. Ex.: 1.9.0."
  type        = string
  default     = "1.9.0"
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling. Defaults to cluster name."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# ArgoCD
# -----------------------------------------------------------------------------
variable "enable_argocd" {
  description = "Enable ArgoCD for GitOps."
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD."
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version (e.g. 6.0.0)."
  type        = string
  default     = "6.0.0"
}

# -----------------------------------------------------------------------------
# Gateway API
# -----------------------------------------------------------------------------
variable "enable_gateway_api" {
  description = "Enable Gateway API with ALB integration."
  type        = bool
  default     = true
}

variable "gateway_api_version" {
  description = "Gateway API Helm chart version (e.g. 1.0.0)."
  type        = string
  default     = "1.2.0"
}

# -----------------------------------------------------------------------------
# EKS Add-ons
# -----------------------------------------------------------------------------
variable "enable_vpc_cni" {
  description = "Enable VPC CNI add-on."
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

variable "enable_coredns" {
  description = "Enable CoreDNS add-on."
  type        = bool
  default     = true
}

variable "enable_kube_proxy" {
  description = "Enable kube-proxy add-on."
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable metrics-server (via Helm or add-on where available)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# IAM Identity Center
# -----------------------------------------------------------------------------
variable "enable_iam_identity_center" {
  description = "Enable EKS access via IAM Identity Center Permission Sets."
  type        = bool
  default     = false
}

variable "permission_set_arn" {
  description = "ARN of the IAM Identity Center Permission Set (for reference)."
  type        = string
  default     = null
}

variable "sso_principal_arn" {
  description = "IAM role ARN created by IAM Identity Center when permission set is assigned (used for EKS Access Entry). Get via: aws iam list-roles --query 'Roles[?starts_with(RoleName, `AWSReservedSSO`)].Arn'."
  type        = string
  default     = null
}

variable "permission_sets" {
  description = "Map of permission set names to config (description, session_duration, cluster_role)."
  type = map(object({
    description      = string
    session_duration = string
    cluster_role     = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC
# -----------------------------------------------------------------------------
variable "enable_github_actions_oidc" {
  description = "Create an opt-in GitHub deploy role with administrator-supplied policies."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub org ou usuário (dono do repositório)."
  type        = string
  default     = "renatosbarretto"
}

variable "github_repo" {
  description = "Nome do repositório no GitHub."
  type        = string
  default     = "blueprint-eks"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Explicit CIDRs allowed to access the public EKS API; empty is allowed only with private-only endpoint."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "Use specific IPv4 CIDRs, not 0.0.0.0/0."
  }
}
variable "github_environment" {
  type    = string
  default = "dev"
}
variable "github_create_oidc_provider" {
  type    = bool
  default = true
}
variable "github_deploy_policy_arns" {
  description = "Existing account-reviewed managed policies for this stack and its S3 state."
  type        = set(string)
  default     = []
}
