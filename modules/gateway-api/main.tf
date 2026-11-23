locals {
  namespace = "gateway-api-system"
  sa_name   = "aws-load-balancer-controller"

  # CRDs versionadas no repo (crds/): sem download em runtime, ficam no state
  # e são removidas no destroy. Para atualizar: baixe a release nova em crds/
  # e ajuste gateway_api_version / lbc_app_version no cartão.
  crd_files = [
    "${path.module}/crds/gateway-api-${var.gateway_api_version}-standard.yaml",
    "${path.module}/crds/lbc-v${var.lbc_app_version}-gateway-crds.yaml",
  ]

  system_scheduling = {
    nodeSelector = { "karpenter.sh/nodepool" = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
  }
}

data "aws_caller_identity" "current" {}

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

resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "lbc" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.lbc.id
  policy = file("${path.module}/iam-policy.json")
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.lbc.arn
  tags            = var.tags
}

resource "kubernetes_namespace_v1" "this" {
  metadata { name = local.namespace }
}

data "kubectl_file_documents" "crds" {
  for_each = toset(local.crd_files)
  content  = file(each.value)
}

locals {
  crd_documents = merge([
    for f, d in data.kubectl_file_documents.crds : {
      for i, doc in d.documents : "${basename(f)}/${i}" => doc
    }
  ]...)
}

resource "kubectl_manifest" "crds" {
  for_each = local.crd_documents

  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = true
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version
  wait       = true
  timeout    = 600

  values = [
    yamlencode(merge(local.system_scheduling, {
      clusterName  = var.cluster_name
      region       = var.region
      vpcId        = var.vpc_id
      replicaCount = 2
      # Réplicas em nós e AZs diferentes: perder um nó não derruba o controller.
      topologySpreadConstraints = [
        for key in ["kubernetes.io/hostname", "topology.kubernetes.io/zone"] : {
          maxSkew           = 1
          topologyKey       = key
          whenUnsatisfiable = key == "kubernetes.io/hostname" ? "DoNotSchedule" : "ScheduleAnyway"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/name"     = "aws-load-balancer-controller"
              "app.kubernetes.io/instance" = "aws-load-balancer-controller"
            }
          }
        }
      ]
      serviceAccount = {
        create = true
        name   = local.sa_name
      }
      controllerConfig = {
        featureGates = {
          ALBGatewayAPI = true
          NLBGatewayAPI = true
        }
      }
    }))
  ]

  depends_on = [
    kubernetes_namespace_v1.this,
    kubectl_manifest.crds,
    aws_eks_pod_identity_association.lbc,
    aws_iam_role_policy.lbc,
  ]
}

resource "kubectl_manifest" "gatewayclass_alb" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "aws-alb"
    }
    spec = {
      controllerName = "gateway.k8s.aws/alb"
    }
  })

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubectl_manifest" "gatewayclass_nlb" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "aws-nlb"
    }
    spec = {
      controllerName = "gateway.k8s.aws/nlb"
    }
  })

  depends_on = [helm_release.aws_load_balancer_controller]
}
