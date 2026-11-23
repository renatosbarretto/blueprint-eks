resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      global = {
        nodeSelector = { "karpenter.sh/nodepool" = "system" }
        tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
      }
      # TLS termina no ALB (Gateway API); o server fala HTTP dentro do cluster.
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        service = { type = "ClusterIP" }
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.this]
}
