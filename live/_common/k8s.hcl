# Providers kubernetes/helm/kubectl para stacks que falam com o cluster.
# Endpoint e CA vêm de data source (cluster precisa existir): sem mock de host
# falso no plan e sem bloco duplicado em cada stack.
# O módulo precisa declarar as variáveis cluster_name e region.
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
data "aws_eks_cluster" "k8s_provider" {
  name = var.cluster_name
}

locals {
  k8s_host = data.aws_eks_cluster.k8s_provider.endpoint
  k8s_ca   = base64decode(data.aws_eks_cluster.k8s_provider.certificate_authority[0].data)
  k8s_exec = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region, "--output", "json"]
}

provider "kubernetes" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.k8s_exec
  }
}

provider "helm" {
  kubernetes {
    host                   = local.k8s_host
    cluster_ca_certificate = local.k8s_ca
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.k8s_exec
    }
  }
}

provider "kubectl" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.k8s_exec
  }
}
EOF
}
