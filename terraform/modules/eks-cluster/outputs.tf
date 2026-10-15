output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_data" {
  description = "Base64-encoded CA certificate for cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster."
  value       = aws_iam_role.cluster.arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA (empty if IRSA disabled)."
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (without https://)."
  value       = var.enable_irsa ? replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "") : null
}

output "ebs_kms_key_arn" {
  description = "EBS KMS key ARN (when create_ebs_kms_key = true)."
  value       = var.create_ebs_kms_key ? aws_kms_key.ebs[0].arn : null
}

output "fargate_pod_execution_role_arn" {
  description = "Fargate pod execution role ARN."
  value       = aws_iam_role.fargate_pod_execution.arn
}
