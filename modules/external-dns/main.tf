locals {
  namespace     = "external-dns"
  sa_name       = "external-dns"
  domain_filter = "${var.environment}.${var.domain_name}"
  zone_arn      = "arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"

  # Zona em outra conta (plano 1 EKS/conta): o external-dns assume uma role lá,
  # e as permissões de Route53 ficam nessa role (aplique a mesma condição de nomes).
  cross_account = var.route53_assume_role_arn != ""

  system_scheduling = {
    nodeSelector = { "karpenter.sh/nodepool" = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# domainFilter é só client-side; o limite real é a condição IAM abaixo:
# este cluster só altera registros sob <environment>.<domain_name>.
data "aws_iam_policy_document" "route53" {
  dynamic "statement" {
    for_each = local.cross_account ? [] : [1]
    content {
      sid       = "ChangeOnlyEnvironmentRecords"
      actions   = ["route53:ChangeResourceRecordSets"]
      resources = [local.zone_arn]
      condition {
        test     = "ForAllValues:StringLike"
        variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
        values   = [local.domain_filter, "*.${local.domain_filter}"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.cross_account ? [] : [1]
    content {
      sid       = "ReadZones"
      actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResources", "route53:ListTagsForResource"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.cross_account ? [1] : []
    content {
      sid       = "AssumeDnsRole"
      actions   = ["sts:AssumeRole"]
      resources = [var.route53_assume_role_arn]
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "external-dns-route53"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.route53.json
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.this.arn
  tags            = var.tags
}

resource "kubernetes_namespace_v1" "this" {
  metadata { name = local.namespace }
}

resource "helm_release" "this" {
  name       = "external-dns"
  namespace  = local.namespace
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version
  wait       = true

  values = [
    yamlencode(merge(local.system_scheduling, {
      provider = {
        name = "aws"
      }
      env = [
        { name = "AWS_DEFAULT_REGION", value = var.region }
      ]
      domainFilters = [local.domain_filter]
      txtOwnerId    = var.cluster_name
      policy        = "upsert-only"
      # Zona hospedada é o parent (brttech.dev); filtro é env.domain (dev.brttech.dev)
      extraArgs = concat(
        ["--aws-zone-match-parent"],
        local.cross_account ? ["--aws-assume-role=${var.route53_assume_role_arn}"] : [],
      )
      # gateway-httproute: DNS a partir de HTTPRoute (Gateway API)
      sources = ["service", "ingress", "gateway-httproute"]
      serviceAccount = {
        create = true
        name   = local.sa_name
      }
    }))
  ]

  depends_on = [
    kubernetes_namespace_v1.this,
    aws_eks_pod_identity_association.this,
    aws_iam_role_policy.this,
  ]
}
