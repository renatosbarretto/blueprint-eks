# -----------------------------------------------------------------------------
# GitHub Actions OIDC — outputs
# -----------------------------------------------------------------------------

output "role_arn" {
  description = "ARN da IAM role que o GitHub Actions deve assumir (use em AWS_ROLE_ARN no secret)."
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Nome da IAM role."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider do GitHub."
  value       = local.oidc_provider_arn
}
