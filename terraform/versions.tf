terraform {
  required_version = ">= 1.11, < 2.0"

  backend "s3" {}

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.7"
    }
  }
}
