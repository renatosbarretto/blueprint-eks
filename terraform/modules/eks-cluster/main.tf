# -----------------------------------------------------------------------------
# KMS key for EKS secrets (etcd encryption)
# -----------------------------------------------------------------------------
resource "aws_kms_key" "eks" {
  description             = "EKS cluster ${var.project_name}-${var.environment} encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-eks-kms"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    security_group_ids      = []
    public_access_cidrs     = length(var.cluster_endpoint_public_access_cidrs) > 0 ? var.cluster_endpoint_public_access_cidrs : null
  }

  # Modo API: autenticação apenas via EKS Access Entries (sem ConfigMap aws-auth).
  # bootstrap_cluster_creator_admin_permissions = true evita replace do cluster (in-place update).
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  bootstrap_self_managed_addons = true

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# OIDC Provider for IRSA
# -----------------------------------------------------------------------------
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Fargate Profile for Karpenter namespace
# -----------------------------------------------------------------------------
resource "aws_eks_fargate_profile" "karpenter" {
  count = var.create_fargate_profile_for_karpenter ? 1 : 0

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "karpenter"
  depends_on             = [aws_iam_role_policy_attachment.fargate_pod_execution_AmazonEKSFargatePodExecutionRolePolicy]
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = var.karpenter_namespace
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Fargate Profile só para CoreDNS (kube-system). Dois selectors: um para a
# label tradicional (k8s-app=kube-dns) e outro para a de componente (eks.amazonaws.com/component=coredns).
# O pod agenda no Fargate se coincidir com QUALQUER um dos selectors.
# -----------------------------------------------------------------------------
resource "aws_eks_fargate_profile" "coredns" {
  count = var.create_fargate_profile_for_kube_system ? 1 : 0

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "coredns"
  depends_on             = [aws_iam_role_policy_attachment.fargate_pod_execution_AmazonEKSFargatePodExecutionRolePolicy]
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
    labels = {
      "k8s-app" = "kube-dns"
    }
  }

  selector {
    namespace = "kube-system"
    labels = {
      "eks.amazonaws.com/component" = "coredns"
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EBS KMS key (for EBS CSI / node volumes) - optional, can use existing
# -----------------------------------------------------------------------------
resource "aws_kms_key" "ebs" {
  count = var.create_ebs_kms_key ? 1 : 0

  description             = "EBS encryption key for ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 to use key"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-ebs-kms"
  })
}

resource "aws_kms_alias" "ebs" {
  count = var.create_ebs_kms_key ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}

# -----------------------------------------------------------------------------
# Initial Managed Node Group (for system add-ons; nodes ready before add-ons)
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "initial" {
  count = var.enable_managed_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "initial"
  node_role_arn   = aws_iam_role.node_group[0].arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_group_instance_types

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
  }

  tags = merge(var.tags, {
    "eks.amazonaws.com/nodegroup" = "initial"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}
