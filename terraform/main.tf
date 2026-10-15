# -----------------------------------------------------------------------------
# Ordem de criação (depends_on / waits) — cluster criado do zero:
#   1. VPC → secondary_network (opcional)
#   2. EKS cluster (control plane + Fargate profiles: coredns + karpenter)
#   3. EKS add-ons bootstrap (vpc-cni + coredns) — CoreDNS nativo com computeType = Fargate
#   4. Karpenter → wait_for_nodes (CRDs, NodePool/EC2NodeClass)
#   5. Add-ons restantes (eks_addons) após Karpenter — EBS CSI etc. sobem com nós já disponíveis
#   6. Em paralelo: ArgoCD | Gateway API (após wait_for_gateway_api_webhook para ArgoCD)
#   7. IAM Identity Center (após cluster)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_vpn_gateway   = var.enable_vpn_gateway
  tags                 = var.tags
}

# -----------------------------------------------------------------------------
# Secondary Network (optional)
# -----------------------------------------------------------------------------
module "secondary_network" {
  source = "./modules/secondary-network"
  count  = var.enable_secondary_network ? 1 : 0

  vpc_id             = module.vpc.vpc_id
  secondary_cidr     = var.secondary_cidr
  availability_zones = var.availability_zones
  project_name       = var.project_name
  environment        = var.environment
  tags               = var.tags
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
module "eks_cluster" {
  source = "./modules/eks-cluster"

  project_name                           = var.project_name
  environment                            = var.environment
  cluster_version                        = var.cluster_version
  vpc_id                                 = module.vpc.vpc_id
  private_subnet_ids                     = module.vpc.private_subnet_ids
  cluster_endpoint_private_access        = var.cluster_endpoint_private_access
  cluster_endpoint_public_access         = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs   = var.cluster_endpoint_public_access_cidrs
  enable_irsa                            = true
  create_fargate_profile_for_karpenter   = var.enable_karpenter && var.karpenter_on_fargate
  create_fargate_profile_for_kube_system = var.enable_karpenter && var.karpenter_on_fargate
  karpenter_namespace                    = var.karpenter_namespace
  create_ebs_kms_key                     = var.enable_ebs_encryption && var.ebs_kms_key_id == null
  enable_managed_node_group              = var.enable_managed_node_group
  node_group_desired_size                = var.node_group_desired_size
  node_group_min_size                    = var.node_group_min_size
  node_group_max_size                    = var.node_group_max_size
  tags                                   = var.tags
}

# -----------------------------------------------------------------------------
# Add-ons de bootstrap: VPC CNI + CoreDNS (config nativa; CoreDNS com computeType = Fargate)
# -----------------------------------------------------------------------------
module "eks_addons_bootstrap" {
  source = "./modules/eks-addons"

  cluster_name             = module.eks_cluster.cluster_name
  cluster_endpoint         = module.eks_cluster.cluster_endpoint
  cluster_certificate_data = module.eks_cluster.cluster_certificate_data
  oidc_provider_arn        = module.eks_cluster.oidc_provider_arn
  oidc_provider_url        = module.eks_cluster.oidc_provider_url

  enable_vpc_cni                   = var.enable_vpc_cni
  enable_vpc_cni_custom_networking = var.enable_vpc_cni_custom_networking
  enable_coredns                   = var.enable_coredns
  coredns_compute_type_fargate     = var.enable_karpenter && var.karpenter_on_fargate
  enable_kube_proxy                = false
  enable_ebs_csi                   = false
  enable_efs_csi                   = false
  enable_metrics_server            = false

  ebs_kms_key_arn = null
  tags            = var.tags

  depends_on = [module.eks_cluster]
}

# -----------------------------------------------------------------------------
# VPC CNI Custom Networking: usar rede secundária (ex.: 10.147) para IPs dos pods
# Cria ENIConfigs por AZ e ativa AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG no aws-node.
# -----------------------------------------------------------------------------
locals {
  vpc_cni_eniconfigs = var.enable_secondary_network && var.enable_vpc_cni_custom_networking && var.enable_vpc_cni && length(module.secondary_network) > 0 && length(try(module.secondary_network[0].secondary_subnet_ids, [])) > 0 ? [
    for i in range(length(var.availability_zones)) : {
      az        = var.availability_zones[i]
      subnet_id = module.secondary_network[0].secondary_subnet_ids[i]
    }
  ] : []
}

resource "local_file" "vpc_cni_eniconfigs" {
  count = var.enable_secondary_network && var.enable_vpc_cni_custom_networking && var.enable_vpc_cni ? 1 : 0

  content = templatefile("${path.module}/templates/vpc-cni-eniconfigs.yaml.tpl", {
    eniconfigs                = local.vpc_cni_eniconfigs
    cluster_security_group_id = module.eks_cluster.cluster_security_group_id
  })
  filename = "${path.module}/generated-vpc-cni-eniconfigs.yaml"
}

# Kubeconfig path para local-exec: evita kubectl usar localhost:8080 (env KUBECONFIG
# em subshell do Terraform pode não ser respeitada). Usar path absoluto e --kubeconfig em todo kubectl.
locals {
  tf_apply_kubeconfig = abspath("${path.module}/.tf-apply-kubeconfig")
}

# Aplica apenas os ENIConfigs (um por AZ, subnets 10.147). As env vars de custom
# networking vêm do add-on via configuration_values (não precisamos de kubectl set env).
resource "null_resource" "vpc_cni_custom_networking" {
  count = var.enable_secondary_network && var.enable_vpc_cni_custom_networking && var.enable_vpc_cni ? 1 : 0

  triggers = {
    eniconfigs = md5(local_file.vpc_cni_eniconfigs[0].content)
    cluster    = module.eks_cluster.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.region} --kubeconfig "${local.tf_apply_kubeconfig}" && \
      kubectl --kubeconfig="${local.tf_apply_kubeconfig}" apply -f ${path.module}/generated-vpc-cni-eniconfigs.yaml
    EOT
    environment = {
      AWS_DEFAULT_REGION = var.region
    }
  }

  depends_on = [module.eks_addons_bootstrap, local_file.vpc_cni_eniconfigs]
}

# -----------------------------------------------------------------------------
# IRSA para aws-node: anotação na ServiceAccount (o add-on nem sempre aplica).
# Sem isto os pods do aws-node não assumem a role e o CNI falha ao criar ENI na rede 10.147.
# -----------------------------------------------------------------------------
resource "kubernetes_annotations" "vpc_cni_irsa_sa" {
  count = var.enable_vpc_cni ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"

  metadata {
    name      = "aws-node"
    namespace = "kube-system"
  }

  annotations = {
    "eks.amazonaws.com/role-arn" = module.eks_addons_bootstrap.vpc_cni_role_arn
  }

  force = true

  depends_on = [module.eks_addons_bootstrap]
}

# Restart do aws-node para os pods passarem a usar a role IRSA (anotação na SA).
resource "null_resource" "aws_node_rollout_after_irsa" {
  count = var.enable_vpc_cni ? 1 : 0

  triggers = {
    role_arn = module.eks_addons_bootstrap.vpc_cni_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.region} --kubeconfig "${local.tf_apply_kubeconfig}" && \
      kubectl --kubeconfig="${local.tf_apply_kubeconfig}" rollout restart daemonset/aws-node -n kube-system
    EOT
    environment = {
      AWS_DEFAULT_REGION = var.region
    }
  }

  depends_on = [kubernetes_annotations.vpc_cni_irsa_sa]
}

# -----------------------------------------------------------------------------
# Karpenter (Fargate profile no eks_cluster; controller no Fargate)
# CoreDNS já sobe no Fargate via add-on (computeType = Fargate), sem patch manual.
# -----------------------------------------------------------------------------
module "karpenter" {
  source = "./modules/karpenter"
  count  = var.enable_karpenter ? 1 : 0

  cluster_name            = module.eks_cluster.cluster_name
  cluster_endpoint        = module.eks_cluster.cluster_endpoint
  cluster_certificate     = module.eks_cluster.cluster_certificate_data
  oidc_provider_arn       = module.eks_cluster.oidc_provider_arn
  oidc_provider_url       = module.eks_cluster.oidc_provider_url
  subnet_ids              = module.vpc.private_subnet_ids
  namespace               = var.karpenter_namespace
  interruption_queue_name = coalesce(var.karpenter_interruption_queue_name, module.eks_cluster.cluster_name)
  run_on_fargate          = var.karpenter_on_fargate
  karpenter_version       = var.karpenter_version
  node_volume_type        = var.node_volume_type
  node_volume_size        = var.node_volume_size
  node_volume_iops        = var.node_volume_iops
  node_volume_throughput  = var.node_volume_throughput
  enable_ebs_kms_policy   = var.enable_ebs_encryption
  helm_values             = [file("${path.module}/../helm/karpenter-values.yaml")]
  ebs_kms_key_arn         = var.enable_ebs_encryption ? (var.ebs_kms_key_id != null ? var.ebs_kms_key_id : module.eks_cluster.ebs_kms_key_arn) : null
  reserved_enis           = (var.enable_secondary_network && var.enable_vpc_cni_custom_networking && var.enable_vpc_cni) ? 1 : 0
  tags                    = var.tags

  depends_on = [module.eks_cluster, module.eks_addons_bootstrap]
}

# -----------------------------------------------------------------------------
# Tags no cluster security group para o EC2NodeClass do Karpenter.
# kubernetes.io/cluster/<name>: shared — usado por EKS para descoberta.
# karpenter.sh/discovery: <name> — recomendado pela doc Karpenter; evita conflito
# com AWS Load Balancer Controller (que suporta só um SG com a tag cluster).
# -----------------------------------------------------------------------------
resource "aws_ec2_tag" "cluster_sg_karpenter" {
  count = var.enable_karpenter ? 1 : 0

  resource_id = module.eks_cluster.cluster_security_group_id
  key         = "kubernetes.io/cluster/${module.eks_cluster.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "cluster_sg_karpenter_discovery" {
  count = var.enable_karpenter ? 1 : 0

  resource_id = module.eks_cluster.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks_cluster.cluster_name
}

# -----------------------------------------------------------------------------
# Provisioners YAML gerado (NodePool + EC2NodeClass) com variáveis do módulo Karpenter
# -----------------------------------------------------------------------------
resource "local_file" "karpenter_provisioners" {
  count = var.enable_karpenter ? 1 : 0
  content = templatefile("${path.module}/templates/karpenter-provisioners.yaml.tpl", {
    cluster_name           = module.eks_cluster.cluster_name
    instance_profile_name  = module.karpenter[0].node_instance_profile_name
    node_volume_size       = var.node_volume_size
    node_volume_type       = var.node_volume_type
    node_volume_iops       = var.node_volume_iops
    node_volume_throughput = var.node_volume_throughput
    enable_ebs_kms_policy  = var.enable_ebs_encryption
    ebs_kms_key_arn        = var.enable_ebs_encryption ? (var.ebs_kms_key_id != null ? var.ebs_kms_key_id : module.eks_cluster.ebs_kms_key_arn) : ""
    encrypted              = var.enable_ebs_encryption
    subnet_ids             = module.vpc.private_subnet_ids
    ami_alias              = var.karpenter_ami_alias
  })
  filename = "${path.module}/generated-karpenter-provisioners.yaml"
}

# -----------------------------------------------------------------------------
# Wait before add-ons: Karpenter deployment available no Fargate, depois aplica NodePool/EC2NodeClass
# Add-ons só rodam após esse recurso (Karpenter pronto + NodePool configurado = nodes sob demanda)
# -----------------------------------------------------------------------------
resource "null_resource" "wait_for_nodes" {
  triggers = {
    cluster_endpoint  = module.eks_cluster.cluster_endpoint
    nodepool_yaml     = var.enable_karpenter ? sha256(local_file.karpenter_provisioners[0].content) : "disabled"
    karpenter_version = var.karpenter_version
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    command = var.enable_karpenter ? (<<-EOT
      aws eks update-kubeconfig --name '${module.eks_cluster.cluster_name}' --region '${var.region}' --kubeconfig '${local.tf_apply_kubeconfig}'
      kubectl --kubeconfig='${local.tf_apply_kubeconfig}' wait --for=condition=available deployment/karpenter -n '${var.karpenter_namespace}' --timeout=600s
      kubectl --kubeconfig='${local.tf_apply_kubeconfig}' apply --server-side -f '${local_file.karpenter_provisioners[0].filename}'
      kubectl --kubeconfig='${local.tf_apply_kubeconfig}' wait --for=condition=Ready ec2nodeclass/default --timeout=600s
    EOT
    ) : "echo 'Using managed node group'"
  }
  depends_on = [module.karpenter, null_resource.vpc_cni_custom_networking, aws_ec2_tag.cluster_sg_karpenter_discovery, aws_ec2_tag.cluster_sg_karpenter]
}

# -----------------------------------------------------------------------------
# EKS Add-ons restantes (após Karpenter e wait_for_nodes: kube-proxy, ebs-csi, metrics-server, etc.)
# -----------------------------------------------------------------------------
module "eks_addons" {
  source = "./modules/eks-addons"

  cluster_name             = module.eks_cluster.cluster_name
  cluster_endpoint         = module.eks_cluster.cluster_endpoint
  cluster_certificate_data = module.eks_cluster.cluster_certificate_data
  oidc_provider_arn        = module.eks_cluster.oidc_provider_arn
  oidc_provider_url        = module.eks_cluster.oidc_provider_url

  enable_vpc_cni        = false # já instalado no bootstrap
  enable_coredns        = false # já instalado no bootstrap
  enable_kube_proxy     = var.enable_kube_proxy
  enable_ebs_csi        = var.enable_ebs_csi
  enable_efs_csi        = var.enable_efs_csi
  enable_metrics_server = var.enable_metrics_server

  enable_ebs_kms_policy = var.enable_ebs_encryption
  ebs_kms_key_arn       = var.enable_ebs_encryption ? (var.ebs_kms_key_id != null ? var.ebs_kms_key_id : module.eks_cluster.ebs_kms_key_arn) : null

  depends_on = [null_resource.wait_for_nodes, module.karpenter]
}

# -----------------------------------------------------------------------------
# Gateway API (após wait_for_nodes; em paralelo com eks_addons para reduzir tempo total)
# -----------------------------------------------------------------------------
module "gateway_api" {
  source = "./modules/gateway-api"
  count  = var.enable_gateway_api ? 1 : 0

  cluster_name        = module.eks_cluster.cluster_name
  cluster_endpoint    = module.eks_cluster.cluster_endpoint
  cluster_certificate = module.eks_cluster.cluster_certificate_data
  oidc_provider_arn   = module.eks_cluster.oidc_provider_arn
  oidc_provider_url   = module.eks_cluster.oidc_provider_url
  vpc_id              = module.vpc.vpc_id
  region              = var.region
  gateway_api_version = var.gateway_api_version
  helm_values         = [file("${path.module}/../helm/gateway-api-values.yaml")]
  tags                = var.tags

  depends_on = [null_resource.wait_for_nodes]
}

# -----------------------------------------------------------------------------
# Esperar webhook do AWS Load Balancer Controller antes do ArgoCD
# Evita "no endpoints available for service aws-load-balancer-webhook-service"
# quando o ArgoCD cria Services e o API server chama o webhook.
# Se Gateway API estiver desabilitado, o wait falha com || true e segue.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ArgoCD (após wait_for_nodes e após webhook do Gateway API estar pronto)
# -----------------------------------------------------------------------------
module "argocd" {
  source = "./modules/argocd"
  count  = var.enable_argocd ? 1 : 0

  cluster_name        = module.eks_cluster.cluster_name
  cluster_endpoint    = module.eks_cluster.cluster_endpoint
  cluster_certificate = module.eks_cluster.cluster_certificate_data
  namespace           = var.argocd_namespace
  argocd_version      = var.argocd_version
  helm_values         = [file("${path.module}/../helm/argocd-values.yaml")]
  tags                = var.tags

  depends_on = [null_resource.wait_for_nodes, module.gateway_api]
}

# -----------------------------------------------------------------------------
# IAM Identity Center (EKS Access Entries + RBAC)
# -----------------------------------------------------------------------------
module "iam_identity_center" {
  source = "./modules/iam-identity-center"
  count  = var.enable_iam_identity_center && var.sso_principal_arn != null ? 1 : 0

  cluster_name                   = module.eks_cluster.cluster_name
  principal_arn                  = var.sso_principal_arn
  permission_set_arn             = var.permission_set_arn
  permission_sets                = var.permission_sets
  rbac_cluster_role_binding_name = "sso-cluster-admin"
  oidc_provider_arn              = module.eks_cluster.oidc_provider_arn
  tags                           = var.tags

  depends_on = [module.eks_cluster]
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC — role para o workflow assumir (sem access key no GitHub)
# Rode terraform apply uma vez; depois configure o secret AWS_ROLE_ARN no repo.
# -----------------------------------------------------------------------------
module "github_actions_oidc" {
  source = "./modules/github-actions-oidc"
  count  = var.enable_github_actions_oidc ? 1 : 0

  github_org           = var.github_org
  github_repo          = var.github_repo
  role_name            = "github-actions-${var.project_name}-${var.environment}"
  allow_environment    = var.github_environment
  create_oidc_provider = var.github_create_oidc_provider
  deploy_policy_arns   = var.github_deploy_policy_arns
  tags                 = var.tags
}

resource "aws_eks_access_entry" "github_actions" {
  count         = var.enable_github_actions_oidc ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.github_actions_oidc[0].role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "github_actions" {
  count         = var.enable_github_actions_oidc ? 1 : 0
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = aws_eks_access_entry.github_actions[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
resource "terraform_data" "configuration" {
  lifecycle {
    precondition {
      condition     = var.enable_managed_node_group || (var.enable_karpenter && var.karpenter_on_fargate && var.enable_coredns)
      error_message = "Bootstrap requires a managed node group or Karpenter and CoreDNS on Fargate."
    }
    precondition {
      condition     = !var.enable_vpc_cni_custom_networking || (var.enable_secondary_network && var.enable_vpc_cni)
      error_message = "Custom networking requires secondary networking and the VPC CNI addon."
    }
    precondition {
      condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
      error_message = "Public EKS access requires an explicit CIDR allowlist."
    }
    precondition {
      condition     = var.cluster_endpoint_private_access || var.cluster_endpoint_public_access
      error_message = "At least one EKS API endpoint must be enabled."
    }
    precondition {
      condition     = !var.enable_iam_identity_center || var.sso_principal_arn != null
      error_message = "SSO requires sso_principal_arn."
    }
    precondition {
      condition     = length(var.availability_zones) >= 2 && length(var.public_subnet_cidrs) == length(var.availability_zones) && length(var.private_subnet_cidrs) == length(var.availability_zones)
      error_message = "Provide at least two AZs and one public/private subnet CIDR per AZ."
    }
  }
}
