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

skip = !local.c.enable_tenants

dependency "eks" {
  config_path                             = "../eks"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/tenants"
}

inputs = merge(
  include.root.inputs,
  {
    tenants = [for t in local.c.tenants : { name = t.name, namespaces = t.namespaces }]
  }
)
