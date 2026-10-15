#!/usr/bin/env bash
# Shared environment isolation. Source only from the operation scripts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
DEPLOY_ENV="${1:?Usage: script dev|staging|prod}"
case "$DEPLOY_ENV" in dev|staging|prod) ;; *) echo 'Invalid environment' >&2; exit 1 ;; esac
export TF_DATA_DIR="${TERRAFORM_DIR}/.tfdata/${DEPLOY_ENV}"
VAR_FILE="${TERRAFORM_DIR}/environments/${DEPLOY_ENV}/terraform.tfvars"
BACKEND_FILE="${TERRAFORM_DIR}/environments/${DEPLOY_ENV}/backend.tfbackend"
PLAN_DIR="${TERRAFORM_DIR}/.plans/${DEPLOY_ENV}"
[[ -f "$VAR_FILE" && -f "$BACKEND_FILE" ]] || { echo "Copy and configure the .example files in environments/${DEPLOY_ENV} first." >&2; exit 1; }
# Environment configs use literal values. Reject mismatches before Terraform can mutate state.
CONFIG_ENV=$(awk -F'"' '/^[[:space:]]*environment[[:space:]]*=/ {print $2}' "$VAR_FILE")
[[ "$CONFIG_ENV" == "$DEPLOY_ENV" ]] || { echo 'tfvars environment does not match the selected environment.' >&2; exit 1; }
BACKEND_KEY=$(awk -F'"' '/^[[:space:]]*key[[:space:]]*=/ {print $2}' "$BACKEND_FILE")
[[ "$BACKEND_KEY" == "eks-blueprint/${DEPLOY_ENV}/terraform.tfstate" ]] || { echo 'Backend key must be eks-blueprint/ENV/terraform.tfstate.' >&2; exit 1; }
mkdir -p "$TF_DATA_DIR" "$PLAN_DIR"
chmod 700 "$PLAN_DIR"
cd "$TERRAFORM_DIR"
