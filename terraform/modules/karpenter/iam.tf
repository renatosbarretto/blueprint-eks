# -----------------------------------------------------------------------------
# Karpenter Controller IRSA
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

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
            "${local.oidc_url}:sub" = "system:serviceaccount:${var.namespace}:karpenter"
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Karpenter controller needs: EC2, Launch Templates, EKS, IAM (instance profile), Pricing, SQS (interruption)
resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-controller"
  role = aws_iam_role.karpenter_controller.id

  policy = templatefile("${path.module}/controller-policy.json.tpl", {
    partition     = "aws"
    region        = data.aws_region.current.id
    account_id    = data.aws_caller_identity.current.account_id
    cluster_name  = var.cluster_name
    node_role_arn = aws_iam_role.karpenter_node.arn
    queue_arn     = aws_sqs_queue.interruption.arn
  })
}

resource "aws_iam_role_policy" "karpenter_kms" {
  count = var.enable_ebs_kms_policy ? 1 : 0
  name  = "karpenter-ebs-kms"
  role  = aws_iam_role.karpenter_controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = var.ebs_kms_key_arn },
      { Effect = "Allow", Action = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"], Resource = var.ebs_kms_key_arn, Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } } }
    ]
  })
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Karpenter Node IAM Role (for EC2 nodes provisioned by Karpenter)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

# -----------------------------------------------------------------------------
# Instance Profile for Karpenter-provisioned nodes
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# -----------------------------------------------------------------------------
# EKS Access Entry so Karpenter node role can join the cluster.
# Type EC2_LINUX: EKS grants node permissions automatically; do not associate
# access policies (AssociateAccessPolicy only allowed for type STANDARD).
# No modo authentication_mode = "API", o tipo EC2_LINUX concede automaticamente
# system:bootstrappers e system:nodes, necessários para o bootstrap AL2023 (nodeadm).
# If this entry already exists (e.g. created outside Terraform), import it:
#   terraform import 'module.karpenter[0].aws_eks_access_entry.karpenter_node' 'CLUSTER_NAME:PRINCIPAL_ARN'
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}
