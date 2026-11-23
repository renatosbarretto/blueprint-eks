include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "k8s" {
  path = "${get_repo_root()}/live/_common/k8s.hcl"
}

locals {
  c = include.root.locals.cluster
}

skip = !local.c.enable_external_secrets

# Pods precisam de nó Ready (NodePool system criado pelo stack karpenter).
dependency "karpenter" {
  config_path                             = "../karpenter"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/external-secrets"
}

inputs = merge(
  include.root.inputs,
  {
    chart_version = local.c.chart_versions.external_secrets
    tenants       = [for t in local.c.tenants : { name = t.name, namespaces = t.namespaces }]
  }
)
