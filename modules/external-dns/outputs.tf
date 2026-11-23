output "role_arn" {
  value = aws_iam_role.this.arn
}

output "domain_filter" {
  value = local.domain_filter
}
