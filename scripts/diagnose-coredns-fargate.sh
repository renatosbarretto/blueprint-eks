#!/usr/bin/env bash
# Diagnóstico: por que o CoreDNS não agenda no Fargate
# Executar com kubeconfig apontando para o cluster EKS.
set -e

echo "=== 1. Labels do pod template do deployment coredns ==="
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.metadata.labels}' 2>/dev/null | jq . 2>/dev/null || kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.metadata.labels}'
echo ""

echo "=== 2. nodeSelector do deployment (deve estar vazio após o patch) ==="
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null | jq . 2>/dev/null || echo "(vazio ou não definido)"
echo ""

echo "=== 3. topologySpreadConstraints do deployment ==="
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' 2>/dev/null | jq . 2>/dev/null || echo "(nenhum)"
echo ""

echo "=== 4. Pods CoreDNS (status e node) ==="
kubectl get pods -n kube-system -l 'k8s-app in (kube-dns)' -o wide 2>/dev/null || true
kubectl get pods -n kube-system -l 'eks.amazonaws.com/component=coredns' -o wide 2>/dev/null || true
echo ""

echo "=== 5. Eventos recentes dos pods coredns ==="
kubectl get events -n kube-system --field-selector involvedObject.name=coredns --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
for p in $(kubectl get pods -n kube-system -o name 2>/dev/null | grep coredns); do
  echo "--- $p ---"
  kubectl describe "$p" -n kube-system 2>/dev/null | grep -A 20 "Events:"
done
echo ""

echo "=== 6. Fargate profiles (AWS CLI; precisa de credenciais) ==="
CLUSTER="${EKS_CLUSTER_NAME:-$(kubectl config current-context 2>/dev/null | cut -d'/' -f2)}"
if command -v aws &>/dev/null && [ -n "$CLUSTER" ]; then
  aws eks list-fargate-profiles --cluster-name "$CLUSTER" --query 'fargateProfileNames' --output text 2>/dev/null || true
  for fp in coredns karpenter; do
    echo "--- Profile: $fp ---"
    aws eks describe-fargate-profile --cluster-name "$CLUSTER" --fargate-profile-name "$fp" --query 'fargateProfile.selectors' --output json 2>/dev/null || true
  done
else
  echo "Defina EKS_CLUSTER_NAME ou use context com nome do cluster; aws CLI necessário."
fi
