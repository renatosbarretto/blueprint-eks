# Decisões de arquitetura

Registro curto das decisões do blueprint (contexto → decisão → consequência).

## 1. Karpenter self-managed (não EKS Auto Mode)

**Contexto:** Auto Mode gerencia Karpenter, CNI, CoreDNS, EBS CSI, LB e patch de AMI, mas cobra
taxa por instância (~10–12% do on-demand). A taxa é fixa por tipo de instância e não cai com Spot
(~25–35% do preço Spot) nem entra em Savings Plans.

**Decisão:** Karpenter self-managed. O blueprint mira produção com escala e Spot.

**Consequência:** a plataforma mantém IAM do Karpenter, interrupção (EventBridge → SQS),
versões de AMI e addons. Reavaliar se o custo operacional superar a taxa.

## 2. Controller do Karpenter e CoreDNS no Fargate

**Contexto:** sem managed node group, alguém precisa rodar o Karpenter antes do primeiro nó.

**Decisão:** Fargate para Karpenter e CoreDNS. Os addons que são DaemonSets (vpc-cni, kube-proxy,
pod-identity-agent) são criados junto com o cluster, antes de existir nó.

**Consequência:** ~US$50/mês de Fargate por cluster. Sem chicken-egg de DNS no bootstrap.

## 3. EKS Pod Identity (exceto Karpenter)

**Decisão:** Pod Identity para vpc-cni, EBS CSI, LBC, external-dns, External Secrets e CloudWatch.
Trust policy única (`pods.eks.amazonaws.com`), reutilizável entre clusters e contas.

**Exceção:** Karpenter usa IRSA. Pod Identity não funciona no Fargate. O OIDC provider existe só por isso.

## 4. NodePool `system` separado

**Decisão:** pool on-demand com taint `CriticalAddonsOnly` para os componentes de plataforma.
Workloads vão para o pool `default` (spot + on-demand, consolidação agressiva).

**Consequência:** 1 nó on-demand sempre ligado por cluster (o deployment `system-capacity-floor`
garante isso). Os controllers de plataforma não sofrem churn de Spot nem de consolidação.

## 5. IAM do Karpenter com escopo por cluster

**Contexto:** os labs compartilham a conta. Uma policy com `Resource: "*"` permitia escalada
(PassRole de qualquer role) e permitia que o Karpenter de um cluster terminasse nós de outro.

**Decisão:** policy oficial v1 com escopo por tag `kubernetes.io/cluster/<cluster>=owned`,
PassRole só na role de nó e instance profile criado pelo Terraform (sem `iam:*InstanceProfile`).
Descoberta de subnets e SG por `karpenter.sh/discovery=<cluster>`.

**Teste:** `modules/karpenter/tests/iam_scope.tftest.hcl`.

## 6. Addons in-cluster via Terraform/Helm (GitOps na fase 2)

**Decisão:** manter Terraform/Helm por enquanto. Providers k8s compartilhados em
`live/_common/k8s.hcl` (endpoint via data source, sem mock de host). Os `local-exec` usam
KUBECONFIG temporário. CRDs do Gateway API ficam versionadas em `modules/gateway-api/crds/`.

**Próximo passo:** Argo CD (self-managed ou EKS Capability) com ApplicationSet por cluster.
O Terraform fica com VPC, EKS e IAM.

## 7. Rede

**Decisão:** VPC de /16 a /18. Subnets públicas /24 e privadas /19 por AZ (o VPC CNI usa um IP
da VPC por pod). NAT `single` em lab e `per_az` em prd. Endpoint S3 gateway sempre ligado; interface
endpoints e flow logs são opcionais por cartão.

## Próximos passos

Ver [roadmap.md](roadmap.md).
