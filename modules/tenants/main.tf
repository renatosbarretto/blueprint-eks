# Namespaces de tenants (squads) com guardrails mínimos:
#   - Pod Security Admission: enforce baseline, warn/audit restricted
#   - LimitRange: requests default (sem requests o Karpenter dimensiona errado)
# Acesso EKS namespace-scoped: root.hcl → modules/eks (access entries).
# Segredos: modules/external-secrets (ClusterSecretStore tenant-<name>).

locals {
  namespaces = merge([
    for t in var.tenants : {
      for ns in t.namespaces : ns => t.name
    }
  ]...)
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = {
      "tenant"                                     = each.value
      "pod-security.kubernetes.io/enforce"         = var.pod_security_enforce
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/audit"           = "restricted"
    }
  }
}

resource "kubernetes_limit_range_v1" "defaults" {
  for_each = local.namespaces

  metadata {
    name      = "defaults"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
      default = {
        memory = "512Mi"
      }
    }
  }
}
