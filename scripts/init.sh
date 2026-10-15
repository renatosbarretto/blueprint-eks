#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh" "$@"
terraform init -input=false -reconfigure -lockfile=readonly -backend-config="$BACKEND_FILE"
