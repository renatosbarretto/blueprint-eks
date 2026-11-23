include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  c = include.root.locals.cluster
}

skip = !local.c.enable_eks

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    private_subnet_ids = ["subnet-mock-a", "subnet-mock-b", "subnet-mock-c"]
    vpc_id             = "vpc-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/eks"
}

inputs = merge(
  include.root.inputs,
  {
    private_subnet_ids         = dependency.vpc.outputs.private_subnet_ids
    cluster_version            = local.c.cluster_version
    support_type               = local.c.support_type
    deletion_protection        = local.c.deletion_protection
    api_public_access_cidrs    = local.c.api_public_access_cidrs
    cluster_log_retention_days = local.c.cluster_log_retention_days
    access_entries             = local.c.access_entries
    enable_breakglass_role     = local.c.enable_breakglass_role
    eks_addon_versions         = local.c.eks_addon_versions
    enable_network_policy      = local.c.enable_network_policy
  }
)
