terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Configurado por scripts/bootstrap-github-oidc.sh (-backend-config):
  # mesmo bucket de state da conta, chave eks-blueprint/_account/github-oidc.
  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "eks-blueprint"
      Component = "github-oidc"
      ManagedBy = "Terraform"
    }
  }
}
