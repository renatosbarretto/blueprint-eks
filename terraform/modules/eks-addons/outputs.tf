output "vpc_cni_addon_version" {
  description = "VPC CNI addon version (when enabled)."
  value       = var.enable_vpc_cni ? aws_eks_addon.vpc_cni[0].addon_version : null
}

output "vpc_cni_role_arn" {
  description = "VPC CNI IRSA role ARN (when enabled)."
  value       = var.enable_vpc_cni ? aws_iam_role.vpc_cni[0].arn : null
}

output "ebs_csi_driver_role_arn" {
  description = "EBS CSI driver IRSA role ARN (when enabled)."
  value       = var.enable_ebs_csi ? aws_iam_role.ebs_csi[0].arn : null
}
