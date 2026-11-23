mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  project            = "eks-blueprint"
  environment        = "dev"
  region             = "us-east-1"
  cluster_name       = "lab-dev"
  vpc_cidr           = "10.10.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

run "subnet_layout_16" {
  command = plan

  assert {
    condition     = local.public_subnet_cidrs == ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    error_message = "Públicas devem ser /24 no primeiro bloco /19."
  }

  assert {
    condition     = local.private_subnet_cidrs == ["10.10.32.0/19", "10.10.64.0/19", "10.10.96.0/19"]
    error_message = "Privadas devem ser /19 por AZ."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["karpenter.sh/discovery"] == "lab-dev"])
    error_message = "Subnets privadas precisam da tag karpenter.sh/discovery=<cluster>."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "nat_gateway_mode=single deve criar 1 NAT."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_flow_log.this) == 0
    error_message = "Defaults não criam interface endpoints nem flow logs."
  }
}

run "prd_like" {
  command = plan

  variables {
    vpc_cidr            = "10.30.0.0/18"
    nat_gateway_mode    = "per_az"
    interface_endpoints = ["ecr.api", "ecr.dkr", "sts"]
    enable_flow_logs    = true
  }

  assert {
    condition     = local.private_subnet_cidrs == ["10.30.8.0/21", "10.30.16.0/21", "10.30.24.0/21"]
    error_message = "Com /18 as privadas devem ser /21."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "per_az deve criar 1 NAT por AZ."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 3 && length(aws_flow_log.this) == 1
    error_message = "Endpoints e flow logs devem ser criados quando habilitados."
  }
}

run "rejects_small_vpc" {
  command = plan

  variables {
    vpc_cidr = "10.10.0.0/20"
  }

  expect_failures = [var.vpc_cidr]
}
