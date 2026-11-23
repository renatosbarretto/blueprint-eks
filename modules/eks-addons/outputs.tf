output "ebs_csi_role_arn" {
  value = try(aws_iam_role.ebs_csi[0].arn, null)
}

output "default_storage_class" {
  value = try(kubernetes_storage_class_v1.gp3[0].metadata[0].name, null)
}
