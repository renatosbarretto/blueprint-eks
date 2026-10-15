#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

cd "$TERRAFORM_DIR"
terraform fmt -recursive -check -diff
terraform validate
echo "Validation OK."
