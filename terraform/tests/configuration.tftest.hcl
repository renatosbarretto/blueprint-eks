mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:role/test" }
  }
  mock_data "aws_region" {
    defaults = { id = "us-east-1", name = "us-east-1" }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
variables {
  project_name                   = "eks-blueprint"
  environment                    = "dev"
  aws_account_id                 = "123456789012"
  availability_zones             = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs            = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs           = ["10.0.11.0/24", "10.0.12.0/24"]
  cluster_endpoint_public_access = false
}
run "default_bootstrap_plan" {
  command = plan
  assert {
    condition     = length(module.karpenter) == 1
    error_message = "Default configuration must bootstrap Karpenter."
  }
}
run "encryption_disabled" {
  command = plan
  variables { enable_ebs_encryption = false }
  assert {
    condition     = length(local_file.karpenter_provisioners) == 1
    error_message = "Unencrypted configuration must still generate the NodePool."
  }
}
run "managed_compute" {
  command = plan
  variables {
    enable_karpenter          = false
    enable_managed_node_group = true
  }
  assert {
    condition     = length(module.karpenter) == 0
    error_message = "Managed-only mode must not install Karpenter."
  }
}
run "reject_no_compute" {
  command = plan
  variables { enable_karpenter = false }
  expect_failures = [terraform_data.configuration]
}
run "reject_public_endpoint_without_allowlist" {
  command = plan
  variables { cluster_endpoint_public_access = true }
  expect_failures = [terraform_data.configuration]
}
run "reject_custom_network_without_secondary" {
  command = plan
  variables { enable_vpc_cni_custom_networking = true }
  expect_failures = [terraform_data.configuration]
}
run "reject_unimplemented_auto_mode" {
  command = plan
  variables { enable_eks_auto_mode = true }
  expect_failures = [var.enable_eks_auto_mode]
}
