#!/usr/bin/env bash
# Apply sequencial (não usa run-all paralelo: a ordem importa por causa dos nós).
# Uso: TG_CLUSTER=lab-dev ./scripts/apply-cluster.sh [--yes]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TG_CLUSTER:?defina TG_CLUSTER (ex: export TG_CLUSTER=lab-dev)}"
export TG_CLUSTER
STACKS_DIR="${ROOT}/live/stacks"

AUTO_APPROVE=()
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE=(-auto-approve)

APPLY_ORDER=(
  vpc
  eks
  karpenter
  eks-addons
  tenants
  gateway-api
  external-dns
  external-secrets
  argocd
)

echo "==> TG_CLUSTER=${TG_CLUSTER}"
python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --check-account

for stack in "${APPLY_ORDER[@]}"; do
  dir="${STACKS_DIR}/${stack}"
  [[ -f "${dir}/terragrunt.hcl" ]] || { echo "skip ${stack}: terragrunt.hcl ausente"; continue; }
  echo ""
  echo "========== APPLY ${stack} =========="
  (
    cd "${dir}"
    # Lock antigo (aws 5.x) quebra com constraint ~> 6.0 após upgrade do módulo.
    terragrunt init -upgrade -reconfigure
    terragrunt apply ${AUTO_APPROVE[@]+"${AUTO_APPROVE[@]}"}
  )
done

echo ""
echo "==> Apply completo: ${TG_CLUSTER}"
