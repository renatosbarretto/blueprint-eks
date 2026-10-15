#!/usr/bin/env bash
set -euo pipefail
# The previous state-less cleanup was unsafe: it could release unrelated EIPs.
# Recovery must restore/import state and review a Terraform destroy plan.
printf '%s\n' \
  'Automatic cleanup without state has been retired.' \
  'Restore the S3 state version (or import resources) before deleting anything.' \
  'Then use scripts/destroy.sh ENV to inspect and confirm the destroy plan.' \
  'See docs/OPERATIONS.md. No AWS resources were changed.' >&2
exit 1
