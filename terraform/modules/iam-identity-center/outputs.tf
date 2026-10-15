output "access_entry_arn" {
  description = "EKS Access Entry ARN for the SSO principal."
  value       = aws_eks_access_entry.sso.principal_arn
}

output "rbac_cluster_role_binding_name" {
  description = "Name of the ClusterRoleBinding for cluster-admin."
  value       = kubernetes_cluster_role_binding_v1.sso_cluster_admin.metadata[0].name
}
