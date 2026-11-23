#!/usr/bin/env bash
# Bootstrap da identidade do GitHub Actions numa conta (uma vez por conta).
# Cria o OIDC provider (se faltar) e as roles eks-blueprint-gha-plan / -apply.
# Uso: TG_CLUSTER=lab-dev ./scripts/bootstrap-github-oidc.sh [--yes]
#      (qualquer cluster da conta serve: conta/região vêm do account.yaml)
# Pré-requisito: scripts/bootstrap-state.sh já rodou na conta.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TG_CLUSTER:?defina TG_CLUSTER (ex: export TG_CLUSTER=lab-dev)}"
DIR="${ROOT}/bootstrap/github-oidc"

python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --check-account

ACCOUNT_ID="$(python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --get account_id)"
REGION="$(python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --get region)"
BUCKET="eks-blueprint-tfstate-${ACCOUNT_ID}"

# Provider já existe (criado fora daqui)? Reusa em vez de falhar com EntityAlreadyExists.
CREATE_PROVIDER=true
if aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" >/dev/null 2>&1; then
  # Se foi este bootstrap que criou, continua gerenciado; senão só referencia.
  if ! (cd "${DIR}" && terraform state list 2>/dev/null | grep -q aws_iam_openid_connect_provider); then
    CREATE_PROVIDER=false
  fi
fi

cd "${DIR}"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=eks-blueprint/_account/github-oidc/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"

VARS=(-var "account_id=${ACCOUNT_ID}" -var "region=${REGION}" -var "state_bucket=${BUCKET}"
      -var "create_oidc_provider=${CREATE_PROVIDER}")

terraform plan -input=false -out=tfplan "${VARS[@]}"
if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Aplicar na conta ${ACCOUNT_ID}? [s/N] " ok
  [[ "${ok}" == "s" ]] || { echo "Abortado."; rm -f tfplan; exit 1; }
fi
terraform apply -input=false tfplan
rm -f tfplan
terraform output
