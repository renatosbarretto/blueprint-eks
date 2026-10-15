output "argocd_namespace" {
  description = "ArgoCD namespace."
  value       = var.namespace
}

output "argocd_endpoint" {
  description = "ArgoCD server endpoint (use kubectl port-forward svc/argocd-server -n argocd 8080:443)."
  value       = "https://argocd-server.${var.namespace}.svc.cluster.local"
}

output "argocd_admin_username" {
  description = "Default ArgoCD admin username."
  value       = "admin"
}
