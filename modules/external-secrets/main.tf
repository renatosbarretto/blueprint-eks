locals {
  namespace = "external-secrets"
  sa_name   = "external-secrets"

  sm_arn  = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret"
  ssm_arn = "arn:aws:ssm:${var.region}:${var.account_id}:parameter"

  # Segredos de plataforma: <cluster>/platform/*  → store "platform" (só namespaces de plataforma)
  # Segredos de tenant:     <cluster>/<tenant>/*  → store "tenant-<tenant>" (só namespaces do tenant)
  tenants = { for t in var.tenants : t.name => t }

  system_scheduling = {
    nodeSelector = { "karpenter.sh/nodepool" = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
  }
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

# Leitura restrita a um prefixo (SM + SSM) — reutilizado por plataforma e tenants.
data "aws_iam_policy_document" "read_prefix" {
  for_each = merge({ platform = "platform" }, { for k, _ in local.tenants : k => k })

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["${local.sm_arn}:${var.cluster_name}/${each.value}/*"]
  }

  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["${local.ssm_arn}/${var.cluster_name}/${each.value}/*"]
  }
}

# --- Controller (Pod Identity): lê segredos de plataforma e assume roles de tenant ---
resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "platform" {
  name   = "platform-secrets"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.read_prefix["platform"].json
}

resource "aws_iam_role_policy" "assume_tenants" {
  count = length(local.tenants) > 0 ? 1 : 0

  name = "assume-tenant-roles"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = [for r in aws_iam_role.tenant : r.arn]
    }]
  })
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.this.arn
  tags            = var.tags
}

# --- Uma role por tenant, assumível só pelo controller ---
data "aws_iam_policy_document" "tenant_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.this.arn]
    }
  }
}

resource "aws_iam_role" "tenant" {
  for_each = local.tenants

  name               = "${var.cluster_name}-eso-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.tenant_assume.json
  tags               = merge(var.tags, { Tenant = each.key })
}

resource "aws_iam_role_policy" "tenant" {
  for_each = local.tenants

  name   = "tenant-secrets"
  role   = aws_iam_role.tenant[each.key].id
  policy = data.aws_iam_policy_document.read_prefix[each.key].json
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace
  }
}

resource "helm_release" "this" {
  name       = "external-secrets"
  namespace  = local.namespace
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version
  wait       = true

  values = [
    yamlencode(merge(local.system_scheduling, {
      installCRDs = true
      serviceAccount = {
        create = true
        name   = local.sa_name
      }
      webhook        = merge(local.system_scheduling, { create = true })
      certController = merge(local.system_scheduling, { create = true })
    }))
  ]

  depends_on = [
    kubernetes_namespace_v1.this,
    aws_eks_pod_identity_association.this,
  ]
}

# Sem bloco auth: usa as credenciais do controller (Pod Identity).
# conditions limita quais namespaces podem referenciar cada store.
resource "kubectl_manifest" "store_platform" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "platform"
    }
    spec = {
      conditions = [{ namespaces = var.platform_namespaces }]
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
        }
      }
    }
  })

  depends_on = [helm_release.this, aws_iam_role_policy.platform]
}

resource "kubectl_manifest" "store_tenant" {
  for_each = local.tenants

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "tenant-${each.key}"
    }
    spec = {
      conditions = [{ namespaces = each.value.namespaces }]
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          role    = aws_iam_role.tenant[each.key].arn
        }
      }
    }
  })

  depends_on = [helm_release.this, aws_iam_role_policy.assume_tenants, aws_iam_role_policy.tenant]
}
