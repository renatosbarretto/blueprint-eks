# -----------------------------------------------------------------------------
# GitHub Actions OIDC — Identity Provider + IAM Role + Policy
# Permite que o workflow assuma uma role sem armazenar AWS_ACCESS_KEY_ID/SECRET.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# OIDC provider do GitHub (um por conta AWS). Se já existir, use create_oidc_provider = false.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Trust policy: apenas este repositório (e opcionalmente um environment) pode assumir a role
locals {
  # GitHub environment must restrict deployments to main.
  sub_claim = "repo:${var.github_org}/${var.github_repo}:environment:${var.allow_environment}"
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  description        = "Role for GitHub Actions (OIDC) - ${var.github_org}/${var.github_repo}"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.sub_claim]
    }
  }
}

# IAM permissions are supplied by the account administrator. No implicit admin policy.
resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = var.deploy_policy_arns
  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}
