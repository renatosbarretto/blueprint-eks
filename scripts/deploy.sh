#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh" "$@"
bash "${SCRIPT_DIR}/init.sh" "$DEPLOY_ENV"
umask 077
PLAN_FILE="${PLAN_DIR}/deploy.tfplan"
trap 'rm -f "$PLAN_FILE"' EXIT
terraform plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN_FILE"
if [[ "${2:-}" != "--yes" ]]; then
  read -r -p "Apply the plan above to ${DEPLOY_ENV}? Type the environment: " confirmation
  [[ "$confirmation" == "$DEPLOY_ENV" ]] || exit 1
fi
terraform apply -input=false -lock-timeout=5m "$PLAN_FILE"
