# Identidade do GitHub Actions na conta:
#   eks-blueprint-gha-plan  → só leitura; assumível por workflows de pull_request.
#   eks-blueprint-gha-apply → administra o blueprint; assumível só por jobs com
#                             GitHub Environment (que exige aprovação e só aceita main).
locals {
  oidc_host = "token.actions.githubusercontent.com"
  oidc_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_host}"
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    plan  = "repo:${var.github_repository}:pull_request"
    apply = "repo:${var.github_repository}:environment:*"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = [each.value]
    }
  }
}

# --- plan ---
resource "aws_iam_role" "plan" {
  name               = "eks-blueprint-gha-plan"
  description        = "GitHub Actions (${var.github_repository}): terragrunt plan em pull requests"
  assume_role_policy = data.aws_iam_policy_document.trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess não lê valores de segredos; o plan não precisa. Deny explícito
# para nunca ler state de outro projeto nem segredos mesmo que a policy AWS mude.
data "aws_iam_policy_document" "plan_guardrails" {
  statement {
    sid       = "NoSecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameter*", "kms:Decrypt"]
    resources = ["*"]
  }
  statement {
    sid           = "StateBucketOnly"
    effect        = "Deny"
    actions       = ["s3:GetObject*"]
    not_resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "plan_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_guardrails.json
}

# --- apply ---
resource "aws_iam_role" "apply" {
  name                 = "eks-blueprint-gha-apply"
  description          = "GitHub Actions (${var.github_repository}): apply aprovado via Environment"
  assume_role_policy   = data.aws_iam_policy_document.trust["apply"].json
  max_session_duration = var.apply_max_session_seconds
}

# Lab: admin. Em conta produtiva, troque por uma policy com os serviços do blueprint
# (eks, ec2, iam com permission boundary, route53, sqs, events, logs, s3 do state).
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
