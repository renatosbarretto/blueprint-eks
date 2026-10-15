#!/usr/bin/env bash
# Debug do VPC CNI com custom networking quando pods falham com:
#   "plugin type=\"aws-cni\" name=\"aws-cni\" failed (add): add cmd: failed to assign an IP address to container"
# Uso: ./scripts/debug-vpc-cni-custom-networking.sh [NODE_NAME]
#      NODE_NAME = opcional; nó onde o pod falha (ex.: ip-10-0-12-126.ec2.internal)
set -e

NODE_NAME="${1:-}"
CLUSTER_NAME="${CLUSTER_NAME:-$(kubectl config current-context 2>/dev/null | cut -d'/' -f2 || true)}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"

echo "=============================================="
echo "  Debug VPC CNI Custom Networking"
echo "  Cluster: ${CLUSTER_NAME:-'(current context)'}"
echo "=============================================="
echo ""

# --- 1. ENIConfigs (nome = AZ, obrigatório para custom networking)
echo "=== 1. ENIConfigs (nome deve ser a AZ, ex.: us-east-1a) ==="
if kubectl get eniconfigs.crd.k8s.amazonaws.com 2>/dev/null; then
  echo ""
  echo "Detalhe (subnet + securityGroups):"
  kubectl get eniconfigs.crd.k8s.amazonaws.com -o custom-columns="NAME:.metadata.name,SUBNET:.spec.subnet,SECURITY_GROUPS:.spec.securityGroups" 2>/dev/null || \
  kubectl get eniconfigs -o yaml 2>/dev/null | grep -E "^(  )?name:|subnet:|securityGroups:" || true
else
  echo "AVISO: CRD ENIConfig não encontrada ou sem recursos. Custom networking exige um ENIConfig por AZ."
fi
echo ""

# --- 2. Nós e label topology.kubernetes.io/zone (tem de bater com o nome do ENIConfig)
echo "=== 2. Nós e label topology.kubernetes.io/zone ==="
kubectl get nodes -o custom-columns="NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone" 2>/dev/null || \
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' 2>/dev/null
echo ""
echo "Cada nó deve ter uma AZ (ex.: us-east-1a). O CNI usa essa AZ para escolher o ENIConfig (nome = AZ)."
echo ""

# --- 3. Conferir nó problemático (se passado como argumento)
if [[ -n "$NODE_NAME" ]]; then
  echo "=== 3. Nó indicado: $NODE_NAME ==="
  ZONE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || true)
  if [[ -z "$ZONE" ]]; then
    echo "AVISO: Nó sem label topology.kubernetes.io/zone. O CNI não consegue escolher o ENIConfig."
  else
    echo "Zona do nó: $ZONE"
    if kubectl get eniconfigs.crd.k8s.amazonaws.com "$ZONE" 2>/dev/null; then
      echo "OK: Existe ENIConfig com nome '$ZONE'."
    else
      echo "ERRO: Não existe ENIConfig com nome '$ZONE'. Crie um ENIConfig com metadata.name=$ZONE para esta AZ."
    fi
  fi
  echo ""
fi

# --- 4. Pods pendentes com evento de falha de IP (ajuda a achar o nó)
echo "=== 4. Pods em Pending/ContainerCreating (possível falha de IP) ==="
PENDING=$(kubectl get pods -A -o wide --field-selector=status.phase=Pending 2>/dev/null | head -20)
if [[ -n "$PENDING" ]]; then
  echo "$PENDING"
  echo ""
  echo "Eventos de um pod pendente (ex.: argocd):"
  FAILED_POD=$(kubectl get pods -A --field-selector=status.phase=Pending -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
  if [[ -n "$FAILED_POD" ]]; then
    echo "kubectl describe pod -n ${FAILED_POD%/*} ${FAILED_POD##*/} | tail -30"
    kubectl describe pod -n "${FAILED_POD%/*}" "${FAILED_POD##*/}" 2>/dev/null | tail -30 || true
  fi
else
  echo "Nenhum pod Pending no momento."
fi
echo ""

# --- 5. DaemonSet aws-node: env vars e ServiceAccount (IRSA)
echo "=== 5. aws-node (DaemonSet): custom networking e IRSA ==="
kubectl get daemonset aws-node -n kube-system -o jsonpath='Custom networking: AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG={.spec.template.spec.containers[0].env[?(@.name=="AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG")].value}, ENI_CONFIG_LABEL_DEF={.spec.template.spec.containers[0].env[?(@.name=="ENI_CONFIG_LABEL_DEF")].value}
ServiceAccount: {.spec.template.spec.serviceAccountName}
' 2>/dev/null || true
echo "Pods aws-node (qual nó e se têm AWS_ROLE_ARN para IRSA):"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName,SA:.spec.serviceAccountName" 2>/dev/null || true
AWS_NODE_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$AWS_NODE_POD" ]]; then
  echo "Exemplo de anotação IRSA num pod aws-node:"
  kubectl get pod -n kube-system "$AWS_NODE_POD" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null && echo "" || echo "(não definida)"
fi
echo ""

# --- 6. Logs do aws-node no nó onde o pod falha
if [[ -n "$NODE_NAME" ]]; then
  echo "=== 6. Logs do aws-node no nó $NODE_NAME (últimas 80 linhas) ==="
  AWS_POD_ON_NODE=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node --field-selector spec.nodeName="$NODE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$AWS_POD_ON_NODE" ]]; then
    kubectl logs -n kube-system "$AWS_POD_ON_NODE" --tail=80 2>/dev/null || echo "Falha ao obter logs."
  else
    echo "Nenhum pod aws-node encontrado no nó $NODE_NAME."
  fi
  echo ""
else
  echo "=== 6. Logs do aws-node ==="
  echo "Para ver logs no nó onde o pod falha, execute:"
  echo "  NODE=ip-10-0-12-126.ec2.internal   # substituir pelo nó do describe pod"
  echo "  POD=\$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node --field-selector spec.nodeName=\$NODE -o jsonpath='{.items[0].metadata.name}')"
  echo "  kubectl logs -n kube-system \$POD --tail=100"
  echo ""
fi

# --- 7. Subnets (disponibilidade de IPs) — requer AWS CLI e REGION
echo "=== 7. Subnets dos ENIConfigs (IPs disponíveis) ==="
if command -v aws &>/dev/null && [[ -n "$REGION" ]]; then
  for ENICFG in $(kubectl get eniconfigs.crd.k8s.amazonaws.com -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    SUBNET_ID=$(kubectl get eniconfigs.crd.k8s.amazonaws.com "$ENICFG" -o jsonpath='{.spec.subnet}' 2>/dev/null)
    if [[ -n "$SUBNET_ID" ]]; then
      CIDR=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_ID" --region "$REGION" --query 'Subnets[0].CidrBlock' --output text 2>/dev/null || true)
      ENI_COUNT=$(aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=$SUBNET_ID" --region "$REGION" --query 'length(NetworkInterfaces)' --output text 2>/dev/null || true)
      echo "ENIConfig $ENICFG -> subnet $SUBNET_ID ($CIDR), ENIs existentes: ${ENI_COUNT:-?}"
    fi
  done
else
  echo "Defina AWS_REGION (ou AWS_DEFAULT_REGION) e tenha aws CLI instalado para ver uso de subnets."
fi
echo ""

# --- 8. Checklist resumido
echo "=============================================="
echo "  Checklist de causas comuns"
echo "=============================================="
echo "1. ENIConfig por AZ: nome = topology.kubernetes.io/zone do nó (ex.: us-east-1a)."
echo "2. Subnet no ENIConfig: mesma VPC do cluster; verificar IPs livres (subnet pequena ou muitas ENIs)."
echo "3. Security group no ENIConfig: normalmente o cluster security group; deve estar na mesma VPC."
echo "4. IRSA: aws-node deve usar ServiceAccount com anotação eks.amazonaws.com/role-arn (add-on com service_account_role_arn)."
echo "5. Nós antigos: após aplicar ENIConfigs, fazer rollout restart do aws-node: kubectl rollout restart daemonset/aws-node -n kube-system"
echo "6. Logs: no nó onde falha, 'kubectl logs -n kube-system <aws-node-pod> --tail=100' para ver erro exacto (ex.: UnauthorizedOperation, insufficient IPs)."
echo ""
