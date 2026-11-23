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

skip = !local.c.enable_gateway_api

dependency "vpc" {
  config_path                             = "../vpc"
  mock_outputs                            = { vpc_id = "vpc-mock" }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

# Pods precisam de nó Ready (NodePool system criado pelo stack karpenter).
dependency "karpenter" {
  config_path                             = "../karpenter"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/gateway-api"
}

inputs = merge(
  include.root.inputs,
  {
    vpc_id              = dependency.vpc.outputs.vpc_id
    lbc_chart_version   = local.c.chart_versions.aws_load_balancer_controller
    lbc_app_version     = local.c.chart_versions.aws_load_balancer_controller
    gateway_api_version = local.c.gateway_api_version
  }
)
