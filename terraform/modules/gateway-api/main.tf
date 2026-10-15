# -----------------------------------------------------------------------------
# Gateway API: AWS Load Balancer Controller (ALB) + Gateway API CRDs
# Gateway API is implemented via CRDs; ALB Controller can satisfy Gateway API
# -----------------------------------------------------------------------------
locals {
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

# -----------------------------------------------------------------------------
# IAM role for AWS Load Balancer Controller (IRSA)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "gateway_api_controller" {
  name = "${var.cluster_name}-gateway-api-controller"

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
            "${local.oidc_url}:sub" = "system:serviceaccount:gateway-api-system:aws-load-balancer-controller"
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "gateway_api_controller" {
  name = "gateway-api-controller"
  role = aws_iam_role.gateway_api_controller.id

  policy = file("${path.module}/iam-policy.json")
}

# -----------------------------------------------------------------------------
# Namespace for Gateway API / ALB Controller
# -----------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "gateway_api" {
  metadata {
    name = "gateway-api-system"
    labels = {
      "app.kubernetes.io/name" = "gateway-api"
    }
  }
}

# -----------------------------------------------------------------------------
# Gateway API CRDs (applied via kubectl - official YAML from kubernetes-sigs)
# -----------------------------------------------------------------------------
resource "null_resource" "gateway_api_crds" {
  triggers = {
    version            = var.gateway_api_version
    controller_version = "2.14.1"
    cluster_endpoint   = var.cluster_endpoint
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    command     = <<-EOT
      export KUBECONFIG=$(mktemp)
      trap 'rm -f "$KUBECONFIG"' EXIT
      aws eks update-kubeconfig --name '${var.cluster_name}' --region '${var.region}' --kubeconfig "$KUBECONFIG"
      kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v${var.gateway_api_version}/standard-install.yaml
      kubectl apply --server-side -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/config/crd/gateway/gateway-crds.yaml
    EOT
  }

  depends_on = [kubernetes_namespace_v1.gateway_api]
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller (works with Gateway API HTTPRoute etc.)
# -----------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = "1.14.1"
  namespace        = kubernetes_namespace_v1.gateway_api.metadata[0].name
  create_namespace = false

  values = concat(var.helm_values, [yamlencode({
    clusterName      = var.cluster_name
    region           = var.region
    vpcId            = var.vpc_id
    controllerConfig = { featureGates = { ALBGatewayAPI = true } }
    serviceAccount = {
      create      = true
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.gateway_api_controller.arn }
    }
  })])
  atomic  = true
  timeout = 900

  depends_on = [
    kubernetes_namespace_v1.gateway_api,
    aws_iam_role_policy.gateway_api_controller,
    null_resource.gateway_api_crds
  ]
}
