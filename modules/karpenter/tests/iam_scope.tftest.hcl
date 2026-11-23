# Provider AWS real (sem credenciais): aws_iam_policy_document é calculado localmente,
# então os asserts olham o JSON verdadeiro da policy do controller.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "kubectl" {}
mock_provider "null" {}

override_data {
  target          = data.aws_caller_identity.current
  override_during = plan
  values          = { account_id = "280912093812" }
}

override_data {
  target          = data.aws_partition.current
  override_during = plan
  values          = { partition = "aws" }
}

variables {
  cluster_name      = "lab-dev"
  cluster_endpoint  = "https://example.eks.amazonaws.com"
  oidc_provider_arn = "arn:aws:iam::280912093812:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/X"
  oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/X"
  karpenter_version = "1.15.1"
  ami_alias         = "al2023@v20261119"
  limits            = { cpu = "10", memory = "40Gi" }
  region            = "us-east-1"
}

run "ami_alias_format" {
  command = plan

  variables {
    ami_alias = "al2023-latest"
  }

  expect_failures = [var.ami_alias]
}

run "controller_policy_is_cluster_scoped" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.controller.json).Statement :
      s.Resource == "arn:aws:iam::280912093812:role/lab-dev-karpenter-node"
      if contains(flatten([s.Action]), "iam:PassRole")
    ])
    error_message = "iam:PassRole deve ser restrito à role de nó do cluster."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.controller.json).Statement :
      try(s.Condition.StringEquals["aws:ResourceTag/kubernetes.io/cluster/lab-dev"], null) == "owned"
      if contains(flatten([s.Action]), "ec2:TerminateInstances")
    ])
    error_message = "ec2:TerminateInstances deve exigir a tag kubernetes.io/cluster/<cluster>=owned."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(data.aws_iam_policy_document.controller.json).Statement :
      anytrue([for a in flatten([s.Action]) : startswith(a, "iam:") && !contains(["iam:PassRole", "iam:GetInstanceProfile", "iam:ListInstanceProfiles", "iam:CreateServiceLinkedRole"], a)])
    ])
    error_message = "Controller não deve gerenciar instance profiles (instanceProfile vem do Terraform)."
  }
}

run "nodeclass_and_interruption" {
  command = plan

  assert {
    condition     = strcontains(kubectl_manifest.ec2nodeclass.yaml_body, "karpenter.sh/discovery")
    error_message = "EC2NodeClass deve selecionar subnets/SG por karpenter.sh/discovery."
  }

  assert {
    condition     = strcontains(kubectl_manifest.ec2nodeclass.yaml_body, "instanceProfile")
    error_message = "EC2NodeClass deve usar instanceProfile do Terraform."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.interruption) == 4
    error_message = "Interrupção precisa das 4 regras EventBridge."
  }
}
