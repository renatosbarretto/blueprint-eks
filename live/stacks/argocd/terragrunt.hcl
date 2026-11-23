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

skip = !local.c.enable_argocd

# Pods precisam de nó Ready (NodePool system criado pelo stack karpenter).
dependency "karpenter" {
  config_path                             = "../karpenter"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/argocd"
}

inputs = merge(
  include.root.inputs,
  {
    argocd_version = local.c.chart_versions.argocd
  }
)
