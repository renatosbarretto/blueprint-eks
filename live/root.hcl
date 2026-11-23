# Cluster selecionado por TG_CLUSTER (obrigatório) = nome do cluster.
# Layout: live/clusters/<ambiente>/<conta>/{account.yaml,<cluster>.yaml}
locals {
  cluster_id = get_env("TG_CLUSTER", "")
  # Sem default de propósito: esquecer o export não pode cair silenciosamente em um cluster.
  # A checagem fica no shell: HCL avalia os dois ramos de um condicional.
  _require_cluster = run_cmd("--terragrunt-quiet", "sh", "-c",
    "[ -n \"$1\" ] || { echo 'ERRO: defina TG_CLUSTER com o nome do cluster (ex: export TG_CLUSTER=lab-dev)' >&2; exit 1; }",
    "sh", local.cluster_id
  )

  live_root     = dirname(find_in_parent_folders("root.hcl"))
  clusters_root = "${local.live_root}/clusters"
  matches       = fileset(local.clusters_root, "*/*/${local.cluster_id}.yaml")
  _require_one = run_cmd("--terragrunt-quiet", "sh", "-c",
    "[ \"$1\" = 1 ] || { echo \"ERRO: TG_CLUSTER=$2 encontrou $1 arquivo(s) em live/clusters/<ambiente>/<conta>/ (esperado 1)\" >&2; exit 1; }",
    "sh", tostring(length(local.matches)), local.cluster_id
  )
  cluster_rel = one(local.matches)

  globals     = yamldecode(file("${local.live_root}/globals.yaml"))
  account_raw = yamldecode(file("${local.clusters_root}/${dirname(local.cluster_rel)}/account.yaml"))
  cluster_raw = yamldecode(file("${local.clusters_root}/${local.cluster_rel}"))

  # Merge raso: defaults ← conta ← cluster. Identidade vem do caminho.
  card = merge(local.globals.defaults, local.account_raw, local.cluster_raw, {
    cluster_name = local.cluster_id
    environment  = split("/", local.cluster_rel)[0]
    account_name = split("/", local.cluster_rel)[1]
  })

  project      = local.card.project
  environment  = local.card.environment
  region       = local.card.region
  account_id   = tostring(local.card.account_id)
  cluster_name = local.card.cluster_name

  access_policy_arns = {
    view  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    edit  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    admin = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
  }

  # Globais + conta + cluster (cluster-scope) + tenants (namespace-scope).
  raw_access_entries = concat(
    try(local.globals.access_entries, []),
    try(local.account_raw.access_entries, []),
    try(local.cluster_raw.access_entries, []),
    [
      for t in local.card.tenants : {
        name               = "tenant-${t.name}"
        principal_arn      = try(t.principal_arn, null)
        sso_permission_set = try(t.sso_permission_set, null)
        policy_arn         = local.access_policy_arns[try(t.access_policy, "edit")]
        namespaces         = t.namespaces
      }
      if try(t.principal_arn, null) != null || try(t.sso_permission_set, null) != null
    ],
  )

  access_entries = [
    for e in local.raw_access_entries : merge(e, {
      principal_arn = try(e.principal_arn, null) == null ? null : replace(
        replace(e.principal_arn, "$${account_id}", local.account_id),
        "$${region}", local.region
      )
    })
  ]

  cluster = merge(local.card, {
    access_entries = local.access_entries
  })

  common_tags = merge(
    {
      Project     = local.project
      Environment = local.environment
      Account     = local.card.account_name
      Cluster     = local.cluster_name
      ManagedBy   = "Terragrunt"
    },
    local.card.extra_tags
  )

  state_bucket = "eks-blueprint-tfstate-${local.account_id}"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = local.state_bucket
    key          = "eks-blueprint/${local.cluster_name}/${basename(get_terragrunt_dir())}/terraform.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true
    # Bucket é gerenciado por scripts/bootstrap-state.sh (versioning, TLS, lifecycle).
    disable_bucket_update = true
  }
}

# allowed_account_ids: credenciais da conta errada abortam o plan/apply.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region              = "${local.region}"
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }
}
EOF
}

inputs = {
  project      = local.project
  environment  = local.environment
  cluster_name = local.cluster_name
  region       = local.region
  account_id   = local.account_id
  tags         = local.common_tags
}
