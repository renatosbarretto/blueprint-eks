# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ips" {
  description = "NAT gateway public IPs (one per AZ)."
  value       = module.vpc.nat_gateway_ips
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID."
  value       = module.eks_cluster.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "EKS cluster IAM role ARN."
  value       = module.eks_cluster.cluster_iam_role_arn
}

# -----------------------------------------------------------------------------
# Karpenter
# -----------------------------------------------------------------------------
output "karpenter_namespace" {
  description = "Karpenter namespace."
  value       = var.enable_karpenter ? module.karpenter[0].namespace : null
}

output "karpenter_service_account_role_arn" {
  description = "Karpenter IRSA role ARN."
  value       = var.enable_karpenter ? module.karpenter[0].karpenter_role_arn : null
}

output "karpenter_irsa_arn" {
  description = "Karpenter IRSA role ARN (alias)."
  value       = var.enable_karpenter ? module.karpenter[0].karpenter_role_arn : null
}

# -----------------------------------------------------------------------------
# ArgoCD
# -----------------------------------------------------------------------------
output "argocd_endpoint" {
  description = "ArgoCD server endpoint (use port-forward or ingress)."
  value       = var.enable_argocd ? module.argocd[0].argocd_endpoint : null
}

output "argocd_admin_username" {
  description = "ArgoCD default admin username."
  value       = var.enable_argocd ? module.argocd[0].argocd_admin_username : null
}

output "argocd_namespace" {
  description = "ArgoCD namespace."
  value       = var.enable_argocd ? module.argocd[0].argocd_namespace : null
}

# -----------------------------------------------------------------------------
# Gateway API
# -----------------------------------------------------------------------------
output "gateway_api_controller_role_arn" {
  description = "Gateway API / ALB controller IAM role ARN."
  value       = var.enable_gateway_api ? module.gateway_api[0].controller_role_arn : null
}

output "gateway_api_namespace" {
  description = "Gateway API controller namespace."
  value       = var.enable_gateway_api ? module.gateway_api[0].gateway_api_namespace : null
}

# -----------------------------------------------------------------------------
# Secondary Network
# -----------------------------------------------------------------------------
output "secondary_vpc_cidr_association_id" {
  description = "Secondary CIDR association ID (when enabled)."
  value       = var.enable_secondary_network ? module.secondary_network[0].secondary_cidr_association_id : null
}

output "secondary_route_table_id" {
  description = "Route table ID for secondary CIDR (when enabled)."
  value       = var.enable_secondary_network ? try(module.secondary_network[0].secondary_route_table_id, null) : null
}

# -----------------------------------------------------------------------------
# IAM Identity Center
# -----------------------------------------------------------------------------
output "eks_access_entry_arn" {
  description = "EKS Access Entry principal ARN for IAM Identity Center (when enabled)."
  value       = var.enable_iam_identity_center && var.sso_principal_arn != null ? module.iam_identity_center[0].access_entry_arn : null
}

output "rbac_cluster_role_binding_name" {
  description = "ClusterRoleBinding name for SSO cluster-admin (when enabled)."
  value       = var.enable_iam_identity_center && var.sso_principal_arn != null ? module.iam_identity_center[0].rbac_cluster_role_binding_name : null
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC
# -----------------------------------------------------------------------------
output "github_actions_role_arn" {
  description = "ARN da role para GitHub Actions (OIDC). Use como secret AWS_ROLE_ARN no repositório."
  value       = var.enable_github_actions_oidc ? module.github_actions_oidc[0].role_arn : null
}
