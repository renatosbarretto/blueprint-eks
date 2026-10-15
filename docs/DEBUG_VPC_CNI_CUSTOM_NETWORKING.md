# Debug: VPC CNI Custom Networking — "failed to assign an IP address to container"

Quando o VPC CNI está em modo **custom networking** (rede secundária, ex.: 10.147), pods podem ficar em `ContainerCreating` com:

```text
Failed to create pod sandbox: plugin type="aws-cni" name="aws-cni" failed (add): add cmd: failed to assign an IP address to container
```

Este doc resume causas comuns e como debugar.

---

## 1. Script de diagnóstico

Execute (opcionalmente passando o nó onde o pod falha):

```bash
# Nó do describe pod (ex.: argocd-application-controller-0 -> Node: ip-10-0-12-126.ec2.internal)
./scripts/debug-vpc-cni-custom-networking.sh ip-10-0-12-126.ec2.internal
```

Ou sem argumento para um resumo geral:

```bash
export AWS_REGION=us-east-1   # para ver uso de subnets
./scripts/debug-vpc-cni-custom-networking.sh
```

O script verifica: ENIConfigs, labels dos nós (AZ), aws-node (env + IRSA), pods pendentes, e sugere como ver logs do `aws-node` no nó problemático.

---

## 2. Causas comuns e correções

| Causa | Como verificar | Correção |
|--------|----------------|----------|
| **ENIConfig com nome errado** | Nome do ENIConfig deve ser **exactamente** a AZ (ex.: `us-east-1a`). O CNI usa a label `topology.kubernetes.io/zone` do nó para escolher o ENIConfig. | Garantir que existe um ENIConfig por AZ e que `metadata.name` = AZ (ex.: `us-east-1a`, `us-east-1b`, `us-east-1c`). Template em `terraform/templates/vpc-cni-eniconfigs.yaml.tpl`. |
| **Nó sem label de zona** | `kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone` | Nós EKS costumam ter a label. Se faltar, adicionar manualmente ou investigar por que o kubelet não a definiu. |
| **Subnet sem IPs** | Ver script secção 7 (ENIs na subnet) ou AWS Console → VPC → Subnets | Aumentar CIDR da subnet secundária, ou usar prefix delegation; garantir que a subnet está na mesma VPC do cluster. |
| **Security group errado** | ENIConfig deve referir um SG da mesma VPC (normalmente cluster SG). | No template usamos `cluster_security_group_id`. Confirmar que o SG existe e está na VPC. |
| **IRSA do aws-node** | `kubectl get pod -n kube-system -l app.kubernetes.io/name=aws-node -o jsonpath='{.items[0].metadata.annotations.eks\.amazonaws\.com/role-arn}'` | Add-on VPC CNI deve ter `service_account_role_arn` e a role com `AmazonEKS_CNI_Policy`. Sem IRSA, o CNI pode falhar ao criar ENI na subnet secundária. |
| **aws-node sem restart após ENIConfig** | ENIConfigs aplicados depois dos nós estarem up. | `kubectl rollout restart daemonset/aws-node -n kube-system` e aguardar novos pods. |
| **Erro IAM (logs)** | Logs do pod `aws-node` no nó: `kubectl logs -n kube-system <aws-node-pod> --tail=100` | Se aparecer `UnauthorizedOperation` ou similar, ajustar a policy da role IRSA (ex.: recursos por subnet/VPC). |

---

## 3. Comandos úteis

```bash
# ENIConfigs
kubectl get eniconfigs.crd.k8s.amazonaws.com -o wide

# Nós e zona
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone

# Logs do aws-node no nó onde o pod falha
NODE=ip-10-0-12-126.ec2.internal
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node --field-selector spec.nodeName=$NODE -o jsonpath='{.items[0].metadata.name}') --tail=100

# Restart do aws-node (aplicar ENIConfig / env após alterações)
kubectl rollout restart daemonset/aws-node -n kube-system
```

---

## 4. Referências

- [Custom networking EKS](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)  
- [AmazonEKS_CNI_Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEKS_CNI_Policy.html)  
- Terraform: `terraform/modules/eks-addons` (add-on vpc-cni + IRSA), `terraform/main.tf` (ENIConfigs), `terraform/templates/vpc-cni-eniconfigs.yaml.tpl`
