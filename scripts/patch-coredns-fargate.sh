#!/usr/bin/env bash
# Reforça o CoreDNS para Fargate: remove anotação que bloqueia, nodeSelector, adiciona toleration, 2 replicas.
# O add-on já pode ter sido criado com computeType=Fargate; este script garante que o deployment fique correto.
# Uso: CLUSTER_NAME=xxx AWS_DEFAULT_REGION=xxx ./patch-coredns-fargate.sh
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
REGION="${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION required}"

KUBECONFIG=$(mktemp)
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" --kubeconfig "$KUBECONFIG"

echo "Waiting for CoreDNS deployment to exist (add-on may be async)..."
for i in $(seq 1 36); do
  if kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 36 ]; then
    echo "Timeout: coredns deployment not found"
    exit 1
  fi
  sleep 5
done

# Pausa para o add-on estabilizar
sleep 15

# Aplica patch até 3 vezes (o add-on pode reverter; queremos ganhar)
for attempt in 1 2 3; do
  echo "Patch attempt $attempt/3..."

  # Remove anotação que impede Fargate (eks.amazonaws.com/compute-type)
  kubectl patch deployment coredns -n kube-system --type=json \
    -p='[{"op":"remove","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]' 2>/dev/null || true

  # nodeSelector vazio + 2 replicas
  kubectl patch deployment coredns -n kube-system --type=merge \
    -p='{"spec":{"replicas":2,"template":{"spec":{"nodeSelector":{}}}}}'

  # Toleration Fargate
  kubectl patch deployment coredns -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"eks.amazonaws.com/compute-type","operator":"Equal","value":"fargate","effect":"NoSchedule"}}]' 2>/dev/null || true

  [ "$attempt" -lt 3 ] && sleep 20
done

# Força recriação dos pods para agendarem no Fargate
kubectl delete pod -n kube-system -l k8s-app=kube-dns --ignore-not-found --timeout=15s || true
kubectl delete pod -n kube-system -l eks.amazonaws.com/component=coredns --ignore-not-found --timeout=15s || true

echo "Waiting for deployment/coredns to be available (up to 10m)..."
kubectl wait --for=condition=available deployment/coredns -n kube-system --timeout=600s
echo "CoreDNS is available on Fargate."
