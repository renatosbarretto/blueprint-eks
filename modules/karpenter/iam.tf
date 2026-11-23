data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_issuer = var.oidc_provider_url
  partition   = data.aws_partition.current.partition
  account_id  = data.aws_caller_identity.current.account_id

  cluster_tag_key = "kubernetes.io/cluster/${var.cluster_name}"
  ec2_arn         = "arn:${local.partition}:ec2:${var.region}"

  # Nomes determinísticos: a policy é calculada no plan (sem esperar recursos).
  node_role_name            = "${var.cluster_name}-karpenter-node"
  node_role_arn             = "arn:${local.partition}:iam::${local.account_id}:role/${local.node_role_name}"
  node_instance_profile_arn = "arn:${local.partition}:iam::${local.account_id}:instance-profile/${local.node_role_name}"
  queue_name                = "${var.cluster_name}-karpenter"
  queue_arn                 = "arn:${local.partition}:sqs:${var.region}:${local.account_id}:${local.queue_name}"
}

# IRSA (não Pod Identity): o controller roda no Fargate, que não suporta Pod Identity.
data "aws_iam_policy_document" "controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.controller_assume.json
  tags               = var.tags
}

# Baseado na policy oficial do Karpenter v1, com escopo por cluster:
# - criação/terminação só de recursos com tag kubernetes.io/cluster/<cluster>=owned
# - PassRole só da role de nó deste cluster
# - instance profile gerenciado pelo Terraform (sem iam:CreateInstanceProfile etc.)
data "aws_iam_policy_document" "controller" {
  statement {
    sid     = "AllowScopedEC2InstanceAccessActions"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.ec2_arn}::image/*",
      "${local.ec2_arn}::snapshot/*",
      "${local.ec2_arn}:*:security-group/*",
      "${local.ec2_arn}:*:subnet/*",
      "${local.ec2_arn}:*:capacity-reservation/*",
    ]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["${local.ec2_arn}:*:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedEC2InstanceActionsWithTags"
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = [
      "${local.ec2_arn}:*:fleet/*",
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:volume/*",
      "${local.ec2_arn}:*:network-interface/*",
      "${local.ec2_arn}:*:launch-template/*",
      "${local.ec2_arn}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedResourceCreationTagging"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.ec2_arn}:*:fleet/*",
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:volume/*",
      "${local.ec2_arn}:*:network-interface/*",
      "${local.ec2_arn}:*:launch-template/*",
      "${local.ec2_arn}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.ec2_arn}:*:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  statement {
    sid     = "AllowScopedDeletion"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowRegionalReadActions"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${var.region}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [local.queue_arn]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    actions   = ["iam:PassRole"]
    resources = [local.node_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    actions   = ["iam:GetInstanceProfile"]
    resources = [local.node_instance_profile_arn]
  }

  # GC de instance profiles do Karpenter lista só o path do próprio cluster (leitura).
  statement {
    sid       = "AllowInstanceProfileListForGC"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/karpenter/${var.region}/${var.cluster_name}/*"]
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    sid       = "AllowSpotServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["spot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

# Com authentication_mode=API, nós EC2 precisam de Access Entry (não aws-auth).
resource "aws_eks_access_entry" "nodes" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = local.node_role_name
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

# Sem AmazonEKS_CNI_Policy: o vpc-cni usa Pod Identity (modules/eks/addons.tf).
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_iam_instance_profile" "node" {
  name = local.node_role_name
  role = aws_iam_role.node.name
  tags = var.tags
}
