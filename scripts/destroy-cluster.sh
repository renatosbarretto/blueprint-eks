#!/usr/bin/env bash
# Destroy sequencial e seguro de UM cluster.
# Uso: TG_CLUSTER=lab-dev ./scripts/destroy-cluster.sh
#
# Ordem:
#   1. Apaga Gateways/Ingress/Services LoadBalancer e espera o LBC remover ALB/NLB
#      (com o controller ainda vivo — é ele quem limpa).
#   2. terragrunt destroy stack a stack, parando no primeiro erro.
#      (stack karpenter: NodePools/EC2NodeClass com wait=true terminam as instâncias
#       antes do controller ser removido.)
#   3. Relatório de sobras com tag do cluster. Só apaga LB/TG com tag
#      elbv2.k8s.aws/cluster=<este cluster> — nunca por prefixo de nome.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TG_CLUSTER:?defina TG_CLUSTER (ex: export TG_CLUSTER=lab-dev)}"
export TG_CLUSTER
STACKS_DIR="${ROOT}/live/stacks"

DESTROY_ORDER=(
  argocd
  external-secrets
  external-dns
  gateway-api
  tenants
  eks-addons
  karpenter
  eks
  vpc
)

python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --check-account

read_card() {
  python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --get "$1"
}

CLUSTER_NAME="$(read_card cluster_name)"
REGION="$(read_card region)"

echo "==> Vai DESTRUIR cluster=${CLUSTER_NAME} region=${REGION} (VPC, EKS, nós, addons, DNS)."
if [[ "${1:-}" == "--yes" ]]; then
  echo "==> --yes: confirmação automática"
else
  read -r -p "Digite o nome do cluster para confirmar: " confirm
  [[ "${confirm}" == "${CLUSTER_NAME}" ]] || { echo "Abortado."; exit 1; }
fi

lb_arns_for_cluster() {
  local arns
  arns="$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "LoadBalancers[].LoadBalancerArn" --output text 2>/dev/null || true)"
  for arn in ${arns}; do
    [[ -z "${arn}" || "${arn}" == "None" ]] && continue
    owner="$(aws elbv2 describe-tags --region "${REGION}" --resource-arns "${arn}" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" --output text 2>/dev/null || true)"
    [[ "${owner}" == "${CLUSTER_NAME}" ]] && echo "${arn}"
  done
}

# --- 1. Remove objetos que criam LB enquanto o LBC está vivo ---
if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  export KUBECONFIG="$(mktemp)"
  trap 'rm -f "${KUBECONFIG}"' EXIT
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null

  echo "==> Removendo Gateways / Ingress / Services LoadBalancer"
  kubectl delete gateways.gateway.networking.k8s.io --all -A --wait=false 2>/dev/null || true
  kubectl delete ingress --all -A --wait=false 2>/dev/null || true
  # Têm finalizer do LBC: se sobrarem depois que o LBC sai, o namespace fica preso em Terminating.
  kubectl delete loadbalancerconfigurations.gateway.k8s.aws,targetgroupconfigurations.gateway.k8s.aws \
    --all -A --wait=false 2>/dev/null || true
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
    | while read -r ns name; do
        [[ -n "${ns}" ]] && kubectl delete svc -n "${ns}" "${name}" --wait=false
      done

  echo "==> Aguardando o LBC remover os load balancers do cluster (até 10 min)"
  for _ in $(seq 1 40); do
    remaining="$(lb_arns_for_cluster | wc -l | tr -d ' ')"
    [[ "${remaining}" -eq 0 ]] && break
    echo "   ${remaining} LB(s) restante(s)..."
    sleep 15
  done
fi

# --- 2. Destroy stack a stack (para no primeiro erro) ---
for stack in "${DESTROY_ORDER[@]}"; do
  dir="${STACKS_DIR}/${stack}"
  [[ -f "${dir}/terragrunt.hcl" ]] || continue
  echo ""
  echo "========== DESTROY ${stack} =========="
  # --non-interactive: sem isso o Terragrunt pergunta sobre stacks dependentes e,
  # sem terminal, desiste com exit 0 (sucesso falso).
  if ! (cd "${dir}" && terragrunt destroy -auto-approve --non-interactive); then
    echo "ERRO: destroy de ${stack} falhou. Corrija e rode o script de novo (é idempotente)." >&2
    exit 1
  fi
  # Não confia só no exit code: o state precisa estar vazio (stacks puladas por skip não têm state).
  left="$(cd "${dir}" && terragrunt state list --non-interactive 2>/dev/null | grep -v '^data\.' || true)"
  if [[ -n "${left}" ]]; then
    echo "ERRO: ${stack} ainda tem recursos no state:" >&2
    echo "${left}" >&2
    exit 1
  fi
done

# --- 3. Sobras com tag deste cluster ---
echo ""
echo "==> Verificando sobras de ${CLUSTER_NAME}"

for arn in $(lb_arns_for_cluster); do
  echo "apagando LB órfão ${arn}"
  aws elbv2 delete-load-balancer --region "${REGION}" --load-balancer-arn "${arn}"
done

tgs="$(aws elbv2 describe-target-groups --region "${REGION}" --query "TargetGroups[].TargetGroupArn" --output text 2>/dev/null || true)"
for arn in ${tgs}; do
  [[ -z "${arn}" || "${arn}" == "None" ]] && continue
  owner="$(aws elbv2 describe-tags --region "${REGION}" --resource-arns "${arn}" \
    --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" --output text 2>/dev/null || true)"
  if [[ "${owner}" == "${CLUSTER_NAME}" ]]; then
    echo "apagando TG órfão ${arn}"
    aws elbv2 delete-target-group --region "${REGION}" --target-group-arn "${arn}" || true
  fi
done

leftover_ec2="$(aws ec2 describe-instances --region "${REGION}" \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)"
if [[ -n "${leftover_ec2}" ]]; then
  echo "ATENÇÃO: instâncias do cluster ainda existem (verifique e termine manualmente): ${leftover_ec2}" >&2
fi

echo ""
echo "==> Destroy completo: ${TG_CLUSTER}"
