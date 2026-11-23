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

skip = !local.c.enable_eks_addons

# Pods precisam de nó Ready (NodePool system criado pelo stack karpenter).
dependency "karpenter" {
  config_path                             = "../karpenter"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/eks-addons"
}

inputs = merge(
  include.root.inputs,
  {
    enable_ebs_csi                  = local.c.enable_ebs_csi
    enable_metrics_server           = local.c.enable_metrics_server
    enable_node_monitoring_agent    = local.c.enable_node_monitoring_agent
    enable_cloudwatch_observability = local.c.enable_cloudwatch_observability
    eks_addon_versions              = local.c.eks_addon_versions
  }
)
