#!/usr/bin/env bash
# Espera o Fargate profile "coredns" ficar ACTIVE.
# Uso: WAIT_FARGATE=1 CLUSTER_NAME=xxx AWS_DEFAULT_REGION=xxx ./wait-fargate-coredns.sh
# Chamado pelo Terraform null_resource.wait_for_fargate_profile_coredns.
set -euo pipefail

if [ "${WAIT_FARGATE:-0}" != "1" ]; then
  echo "Fargate for CoreDNS disabled; skipping wait for profile coredns."
  exit 0
fi

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
REGION="${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION required}"

echo "Waiting for Fargate profile 'coredns' to become ACTIVE..."
for i in $(seq 1 60); do
  status=$(aws eks describe-fargate-profile \
    --cluster-name "$CLUSTER_NAME" \
    --fargate-profile-name coredns \
    --region "$REGION" \
    --query 'fargateProfile.status' --output text 2>/dev/null || echo "CREATING")
  echo "  [$i/60] status=$status"
  if [ "$status" = "ACTIVE" ]; then
    echo "Fargate profile coredns is ACTIVE."
    exit 0
  fi
  if [ "$i" -eq 60 ]; then
    echo "Timeout: Fargate profile coredns did not become ACTIVE."
    exit 1
  fi
  sleep 15
done
