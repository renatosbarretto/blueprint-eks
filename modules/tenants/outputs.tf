output "namespaces" {
  value = { for ns, t in local.namespaces : ns => t }
}
