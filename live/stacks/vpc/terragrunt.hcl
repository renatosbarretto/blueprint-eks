include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  c = include.root.locals.cluster
}

skip = !local.c.enable_vpc

terraform {
  source = "${get_repo_root()}/modules/vpc"
}

inputs = merge(
  include.root.inputs,
  {
    vpc_cidr                 = local.c.vpc_cidr
    availability_zones       = local.c.availability_zones
    nat_gateway_mode         = local.c.nat_gateway_mode
    interface_endpoints      = local.c.vpc_interface_endpoints
    enable_flow_logs         = local.c.enable_flow_logs
    flow_logs_retention_days = local.c.flow_logs_retention_days
  }
)
