output "controller_role_arn" {
  value = aws_iam_role.lbc.arn
}

output "namespace" {
  value = local.namespace
}
