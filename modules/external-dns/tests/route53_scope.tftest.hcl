# Provider AWS real (sem credenciais): aws_iam_policy_document é calculado localmente,
# então o teste inspeciona o JSON verdadeiro da policy.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target          = data.aws_caller_identity.current
  override_during = plan
  values          = { account_id = "280912093812" }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "kubectl" {}

variables {
  cluster_name           = "lab-dev"
  domain_name            = "brttech.dev"
  route53_hosted_zone_id = "ZTEST"
  environment            = "dev"
  region                 = "us-east-1"
  chart_version          = "1.15.0"
}

run "change_limited_to_environment_subdomain" {
  command = plan

  assert {
    condition     = local.domain_filter == "dev.brttech.dev"
    error_message = "domain_filter deve ser <env>.<domain>, nunca o apex."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(data.aws_iam_policy_document.route53.json).Statement :
      try(s.Condition["ForAllValues:StringLike"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"], null) != null
    ])
    error_message = "ChangeResourceRecordSets precisa da condição de nomes por ambiente."
  }
}
