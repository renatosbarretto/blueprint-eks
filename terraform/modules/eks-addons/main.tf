# -----------------------------------------------------------------------------
# VPC CNI - IAM role (IRSA) para o service account kube-system:aws-node
# Necessário para o CNI gerir ENIs e usar custom networking (ex.: rede 10.147).
# -----------------------------------------------------------------------------
resource "aws_iam_role" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0

  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni[0].name
}

# -----------------------------------------------------------------------------
# VPC CNI Add-on
# Custom networking (rede 10.147): env vars via configuration_values do add-on
# em vez de kubectl set env — assim o add-on gerido não sobrescreve a config.
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
  count      = var.enable_vpc_cni ? 1 : 0

  cluster_name             = var.cluster_name
  addon_name               = "vpc-cni"
  addon_version            = null # use latest compatible
  service_account_role_arn = aws_iam_role.vpc_cni[0].arn
  # ENABLE_PREFIX_DELEGATION vital para mais pods por nó (rede 10.147 e AL2023/Nitro).
  configuration_values = var.enable_vpc_cni_custom_networking ? jsonencode({
    env = {
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
      ENABLE_PREFIX_DELEGATION           = "true"
    }
  }) : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CoreDNS Add-on (after VPC CNI). computeType = Fargate nativo evita patch manual.
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  count = var.enable_coredns ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = null
  configuration_values        = var.coredns_compute_type_fargate ? jsonencode({ computeType = "Fargate" }) : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags

  depends_on = [aws_eks_addon.vpc_cni]
}

# -----------------------------------------------------------------------------
# Kube-proxy Add-on
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_kube_proxy ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EBS CSI Driver - IAM role (IRSA)
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi[0].name
}

# KMS policy for EBS encryption when key is provided
resource "aws_iam_role_policy" "ebs_csi_kms" {
  count = var.enable_ebs_csi && var.enable_ebs_kms_policy ? 1 : 0

  name = "ebs-csi-kms"
  role = aws_iam_role.ebs_csi[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = var.ebs_kms_key_arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EBS CSI Driver Add-on
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "ebs_csi" {
  depends_on = [aws_iam_role_policy_attachment.ebs_csi, aws_iam_role_policy.ebs_csi_kms]
  count      = var.enable_ebs_csi ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = null
  service_account_role_arn    = aws_iam_role.ebs_csi[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EFS CSI Driver (optional)
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "efs_csi" {
  service_account_role_arn = aws_iam_role.efs_csi[0].arn
  depends_on               = [aws_iam_role_policy_attachment.efs_csi]
  count                    = var.enable_efs_csi ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Metrics Server (Helm - after Core DNS so cluster is stable)
# -----------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  version          = "3.12.2"
  create_namespace = false

  set = [
    { name = "args[0]", value = "--kubelet-preferred-address-types=InternalIP" }
  ]

  depends_on = [aws_eks_addon.coredns]
}

resource "aws_iam_role" "efs_csi" {
  count = var.enable_efs_csi ? 1 : 0

  name = "${var.cluster_name}-efs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = var.enable_efs_csi ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi[0].name
}

