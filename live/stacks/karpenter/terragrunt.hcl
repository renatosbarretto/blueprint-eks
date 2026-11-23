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

skip = !local.c.enable_karpenter

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_endpoint  = "https://mock.eks.amazonaws.com"
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

# Sem dependency em eks-addons: EBS CSI / metrics-server precisam de nó EC2.
# vpc-cni/kube-proxy/coredns/pod-identity-agent já vêm do stack eks.

terraform {
  source = "${get_repo_root()}/modules/karpenter"
}

inputs = merge(
  include.root.inputs,
  {
    cluster_endpoint  = dependency.eks.outputs.cluster_endpoint
    oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
    oidc_provider_url = dependency.eks.outputs.oidc_provider_url
    karpenter_version = local.c.karpenter_version
    replicas          = local.c.karpenter_replicas
    ami_alias         = local.c.karpenter_ami_alias
    arch              = local.c.karpenter_arch
    capacity_types    = local.c.karpenter_capacity_types
    limits            = local.c.karpenter_limits
  }
)
