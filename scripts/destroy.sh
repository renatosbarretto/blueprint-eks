#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh" "$@"
bash "${SCRIPT_DIR}/init.sh" "$DEPLOY_ENV"
umask 077
PLAN_FILE="${PLAN_DIR}/destroy.tfplan"
trap 'rm -f "$PLAN_FILE"' EXIT
terraform plan -destroy -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN_FILE"
read -r -p "Destroy ${DEPLOY_ENV} using the plan above? Type destroy-${DEPLOY_ENV}: " confirmation
[[ "$confirmation" == "destroy-${DEPLOY_ENV}" ]] || exit 1
terraform apply -input=false -lock-timeout=5m "$PLAN_FILE"
