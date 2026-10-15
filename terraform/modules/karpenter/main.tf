# -----------------------------------------------------------------------------
# Namespace (so Fargate profile can schedule pods here)
# -----------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name" = "karpenter"
    }
  }
}

# -----------------------------------------------------------------------------
# Karpenter Helm chart (OCI)
# -----------------------------------------------------------------------------
resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  namespace        = kubernetes_namespace_v1.karpenter.metadata[0].name
  create_namespace = false

  # values com yamlencode garante que tipos booleanos (featureGates) sejam passados corretamente ao Helm
  values = concat(var.helm_values, [yamlencode({
    replicas                  = var.run_on_fargate ? 1 : 2
    nodeSelector              = var.run_on_fargate ? { "eks.amazonaws.com/compute-type" = "fargate" } : { "kubernetes.io/os" = "linux" }
    topologySpreadConstraints = []
    affinity = {
      nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{ matchExpressions = [{ key = "karpenter.sh/nodepool", operator = "DoesNotExist" }] }]
        }
      }
      podAntiAffinity = var.run_on_fargate ? null : {
        preferredDuringSchedulingIgnoredDuringExecution = [{ weight = 100, podAffinityTerm = { topologyKey = "kubernetes.io/hostname", labelSelector = { matchLabels = { "app.kubernetes.io/name" = "karpenter" } } } }]
      }
    }
    serviceAccount = {
      create      = true
      name        = "karpenter"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn }
    }
    settings = {
      clusterName       = var.cluster_name
      clusterEndpoint   = var.cluster_endpoint
      interruptionQueue = local.interruption_queue_name_full
      reservedENIs      = tostring(var.reserved_enis)
      featureGates      = { reservedCapacity = false, staticCapacity = false, spotToSpotConsolidation = false, nodeRepair = false, nodeOverlay = false }
    }
  })])
  timeout = 900
  atomic  = true

  depends_on = [
    kubernetes_namespace_v1.karpenter,
    aws_iam_role_policy.karpenter_controller,
    aws_iam_role_policy.karpenter_kms,
    aws_iam_role_policy_attachment.karpenter_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.karpenter_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_instance_profile.karpenter_node,
    aws_eks_access_entry.karpenter_node,
    aws_sqs_queue.interruption,
  ]
}
