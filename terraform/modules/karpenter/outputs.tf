output "namespace" {
  description = "Karpenter namespace."
  value       = var.namespace
}

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN."
  value       = aws_iam_role.karpenter_controller.arn
}

output "node_instance_profile_name" {
  description = "Instance profile name for Karpenter-provisioned nodes."
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "karpenter_node_role_arn" {
  description = "IAM role ARN for Karpenter-provisioned EC2 nodes (EKS Access Entry EC2_LINUX)."
  value       = aws_iam_role.karpenter_node.arn
}
