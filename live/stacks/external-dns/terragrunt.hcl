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

skip = !local.c.enable_external_dns

# Pods precisam de nó Ready (NodePool system criado pelo stack karpenter).
dependency "karpenter" {
  config_path                             = "../karpenter"
  skip_outputs                            = true
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

terraform {
  source = "${get_repo_root()}/modules/external-dns"
}

inputs = merge(
  include.root.inputs,
  {
    domain_name             = local.c.domain_name
    route53_hosted_zone_id  = local.c.route53_hosted_zone_id
    route53_assume_role_arn = local.c.route53_assume_role_arn
    chart_version           = local.c.chart_versions.external_dns
  }
)
