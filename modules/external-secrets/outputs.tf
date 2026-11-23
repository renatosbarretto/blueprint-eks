output "namespace" {
  value = local.namespace
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "cluster_secret_stores" {
  description = "Store por tenant (tenant-<name>) + platform."
  value       = concat(["platform"], [for k, _ in local.tenants : "tenant-${k}"])
}

output "tenant_role_arns" {
  value = { for k, r in aws_iam_role.tenant : k => r.arn }
}
