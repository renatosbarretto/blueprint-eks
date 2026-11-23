# Addons que precisam de nó EC2 (rodam depois do Karpenter criar o nó system).
# vpc-cni / kube-proxy / coredns / pod-identity-agent ficam em modules/eks.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  partition = data.aws_partition.current.partition

  enabled_addons = toset(compact([
    var.enable_ebs_csi ? "aws-ebs-csi-driver" : "",
    var.enable_metrics_server ? "metrics-server" : "",
    var.enable_node_monitoring_agent ? "eks-node-monitoring-agent" : "",
    var.enable_cloudwatch_observability ? "amazon-cloudwatch-observability" : "",
  ]))
}

data "aws_eks_addon_version" "this" {
  for_each = local.enabled_addons

  addon_name         = each.key
  kubernetes_version = data.aws_eks_cluster.this.version
}

locals {
  addon_version = {
    for k, v in data.aws_eks_addon_version.this : k => lookup(var.eks_addon_versions, k, v.version)
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
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# --- EBS CSI (Pod Identity) ---
resource "aws_iam_role" "ebs_csi" {
  count              = var.enable_ebs_csi ? 1 : 0
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.enable_ebs_csi ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = local.addon_version["aws-ebs-csi-driver"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi[0].arn
    service_account = "ebs-csi-controller-sa"
  }

  tags       = var.tags
  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}

# StorageClass default: clusters novos não marcam gp2 como default → PVC sem
# storageClassName ficaria Pending.
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.enable_ebs_csi ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

resource "aws_eks_addon" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "metrics-server"
  addon_version               = local.addon_version["metrics-server"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

# Reporta problemas de nó (kernel, rede, disco, GPU) como NodeConditions.
resource "aws_eks_addon" "node_monitoring_agent" {
  count = var.enable_node_monitoring_agent ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "eks-node-monitoring-agent"
  addon_version               = local.addon_version["eks-node-monitoring-agent"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

# --- Container Insights + logs de aplicação (CloudWatch; tem custo por métrica/log) ---
resource "aws_iam_role" "cloudwatch" {
  count              = var.enable_cloudwatch_observability ? 1 : 0
  name               = "${var.cluster_name}-cloudwatch-observability"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  for_each = var.enable_cloudwatch_observability ? toset(["CloudWatchAgentServerPolicy", "AWSXrayWriteOnlyAccess"]) : toset([])

  role       = aws_iam_role.cloudwatch[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_cloudwatch_observability ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = local.addon_version["amazon-cloudwatch-observability"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch[0].arn
    service_account = "cloudwatch-agent"
  }

  tags       = var.tags
  depends_on = [aws_iam_role_policy_attachment.cloudwatch]
}
