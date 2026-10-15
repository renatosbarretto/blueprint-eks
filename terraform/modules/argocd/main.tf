# -----------------------------------------------------------------------------
# ArgoCD namespace
# -----------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }
}

# -----------------------------------------------------------------------------
# ArgoCD Helm release
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = kubernetes_namespace_v1.argocd.metadata[0].name
  create_namespace = false

  values = var.helm_values

  depends_on = [kubernetes_namespace_v1.argocd]
}
