#!/usr/bin/env bash
# Verifica se o VPC CNI está configurado para custom networking (rede 10.147).
# Requer: kubectl configurado para o cluster EKS.
set -e

echo "=== 1. ENIConfigs (devem existir um por AZ, com subnet do 10.147) ==="
kubectl get eniconfigs 2>/dev/null || kubectl get eniconfigs.crd.k8s.amazonaws.com 2>/dev/null || echo "CRD ENIConfig não encontrada."
echo ""

echo "=== 2. DaemonSet aws-node: variáveis de custom networking ==="
kubectl get daemonset aws-node -n kube-system -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG")]}{.name}={.value}{"\n"}{end}' 2>/dev/null || true
kubectl get daemonset aws-node -n kube-system -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="ENI_CONFIG_LABEL_DEF")]}{.name}={.value}{"\n"}{end}' 2>/dev/null || true
echo ""

echo "=== 3. Pod IPs (pods com IP 10.147.x são da rede secundária) ==="
echo "Primeiras 20 linhas de 'kubectl get pods -A -o wide':"
kubectl get pods -A -o wide 2>/dev/null | head -20
echo ""
echo "Pods com IP na rede 10.147:"
kubectl get pods -A -o wide 2>/dev/null | grep "10\.147\." || echo "Nenhum pod com IP 10.147.x (normal se só existirem nós antigos)."
echo ""

echo "=== 4. Importante ==="
echo "Custom networking aplica-se apenas a NÓS NOVOS. Nós que já existiam"
echo "antes de ativar continuam a usar a rede primária (10.0.x) para pods."
echo "Para ver IPs 10.147: substitua nós (cordon/drain e deixe o Karpenter"
echo "criar novos) ou scale um deployment para forçar novos pods em novos nós."
