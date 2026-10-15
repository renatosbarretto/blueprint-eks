#!/usr/bin/env bash
# Safely drain one explicit EC2 node; no cluster-wide restart.
set -euo pipefail
CONTEXT="${1:?Usage: script EXPECTED_CONTEXT NODE}"
NODE="${2:?Provide one node name}"
[[ "$(kubectl config current-context)" == "$CONTEXT" ]] || { echo 'Wrong Kubernetes context' >&2; exit 1; }
COMPUTE=$(kubectl --context="$CONTEXT" get node "$NODE" -o 'jsonpath={.metadata.labels.eks\.amazonaws\.com/compute-type}')
[[ "$COMPUTE" != fargate ]] || { echo 'Fargate nodes cannot be drained with this script.' >&2; exit 1; }
read -r -p "Drain ${NODE} on ${CONTEXT}? Type the node name: " confirmation
[[ "$confirmation" == "$NODE" ]] || exit 1
kubectl --context="$CONTEXT" cordon "$NODE"
trap 'kubectl --context="$CONTEXT" uncordon "$NODE"' ERR
# Respect PDBs and local data. No --force / --disable-eviction / --delete-emptydir-data.
kubectl --context="$CONTEXT" drain "$NODE" --ignore-daemonsets --timeout=15m
printf 'Node %s is drained and cordoned; inspect it before removal.\n' "$NODE"
