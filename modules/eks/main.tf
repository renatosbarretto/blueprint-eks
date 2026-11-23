locals {
  cluster_name = var.cluster_name

  access_entries_lookup = {
    for e in var.access_entries : e.name => e
    if try(e.principal_arn, null) == null || e.principal_arn == ""
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Resolve role SSO do Identity Center na conta atual (sufixo muda / path pode ser regional).
data "aws_iam_roles" "sso" {
  for_each = local.access_entries_lookup

  name_regex  = "AWSReservedSSO_${each.value.sso_permission_set}_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  access_entries = merge(
    {
      for e in var.access_entries : e.name => {
        policy_arn = e.policy_arn
        namespaces = e.namespaces == null ? [] : e.namespaces
        principal_arn = (
          try(e.principal_arn, null) != null && e.principal_arn != ""
          ? e.principal_arn
          : one(data.aws_iam_roles.sso[e.name].arns)
        )
      }
    },
    var.enable_breakglass_role ? {
      breakglass = {
        policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        namespaces    = []
        principal_arn = aws_iam_role.breakglass[0].arn
      }
    } : {}
  )
}

# Criado antes do cluster: senão o EKS cria o log group sem retenção (custo infinito).
resource "aws_cloudwatch_log_group" "cluster" {
  # checkov:skip=CKV_AWS_158: criptografia default do CloudWatch Logs; CMK é decisão por conta/compliance
  # checkov:skip=CKV_AWS_338: retenção vem do cartão (cluster_log_retention_days), 30d em lab
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  # checkov:skip=CKV_AWS_58: EKS aplica envelope encryption default (chave AWS) nos dados da API; CMK é opcional
  # checkov:skip=CKV_AWS_37: controllerManager/scheduler omitidos por custo; api/audit/authenticator ativos
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # Addons core vêm de aws_eks_addon (versionados), não do bootstrap self-managed.
  bootstrap_self_managed_addons = false
  deletion_protection           = var.deletion_protection

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.api_public_access_cidrs) > 0
    public_access_cidrs     = length(var.api_public_access_cidrs) > 0 ? var.api_public_access_cidrs : null
  }

  access_config {
    authentication_mode = "API"
    # Access Entries no YAML cobrem o admin; evita 409 ResourceInUse no creator.
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = var.support_type
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]

  tags = var.tags
}

# Karpenter seleciona o SG dos nós por esta tag.
resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}

# OIDC só para o Karpenter: roda no Fargate, onde EKS Pod Identity não funciona.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  tags            = var.tags
}

resource "aws_eks_fargate_profile" "karpenter" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "karpenter"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = var.karpenter_namespace
  }

  tags = var.tags
}

# Só CoreDNS no Fargate (não o namespace kube-system inteiro).
resource "aws_eks_fargate_profile" "coredns" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "coredns"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
    labels = {
      "k8s-app" = "kube-dns"
    }
  }

  tags = var.tags
}

resource "aws_eks_access_entry" "this" {
  for_each = local.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}
