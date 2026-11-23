# Roadmap

Próximos módulos, na ordem sugerida. A ordem importa: a escolha de CNI (Cilium) muda o desenho
do CIDR de pods, e os dois mexem na fundação da rede, que **exige recriar o cluster**.

| # | Item | Decisão | Impacto |
|---|---|---|---|
| 1 | Cilium | **chaining** com VPC CNI (decidido 2026-11-22) | recria cluster |
| 2 | CIDR de pods não roteado | **`100.64.0.0/16`** (decidido 2026-11-22) | recria VPC/cluster |
| 3 | DNS interno `brttech.cloud` | **congelado** (ambiente é lab) | aditivo |
| 4 | KEDA, HPA, VPA | estratégia na seção 4 | aditivo |
| 5 | GitOps (Argo CD) para os addons | — | muda como os addons são entregues |
| 6 | Backlog de hardening | — | aditivo |

---

## 1. Cilium

Três modos possíveis. **Decidir antes do item 2.**

| Modo | Quem faz IPAM/rota | IP do pod | Prós | Contras |
|---|---|---|---|---|
| **Chaining** com VPC CNI | VPC CNI | IP da VPC (ou 100.64 com custom networking) | menor mudança; mantém ALB `target-type: ip`, Pod Identity, tudo deste blueprint; ganha Hubble e políticas L7 | dois componentes de rede para operar |
| **ENI mode** | Cilium (IPAM AWS) | IP da VPC | substitui o VPC CNI; pode trocar o kube-proxy | o addon `vpc-cni` sai; precisa de IAM próprio para ENIs |
| **Overlay** (VXLAN/Geneve) | Cilium (cluster-pool) | faixa privada qualquer, fora da VPC | pods não consomem IP da VPC; dispensa o item 2 | o control plane EKS **não alcança** pods: webhooks (LBC, ESO, …) precisam de `hostNetwork`; ALB `target-type: ip` deixa de funcionar (só `instance`/NodePort) |

**Decisão: chaining.** Mantém ALB por IP, Pod Identity e webhooks alcançáveis.
O overlay quebra pressupostos usados hoje: ALB por IP e webhooks alcançáveis.

Ao implementar:
- Adicionar uma `startupTaint` `node.cilium.io/agent-not-ready` nos NodePools do Karpenter, para
  nenhum pod subir antes do agente.
- Escolher **um** motor de NetworkPolicy: desligar `enable_network_policy` do VPC CNI se o Cilium
  cuidar das políticas.
- O agente roda como DaemonSet e precisa tolerar o taint `CriticalAddonsOnly` do pool `system`.

## 2. CIDR de pods não roteado

> **Atenção:** `10.147.0.0/8` não é uma faixa válida para isso. Um /8 ignora os bits seguintes e
> equivale a `10.0.0.0/8`, que se sobrepõe às VPCs (`10.10/16`, `10.20/16`, `10.30/16`) e às redes
> corporativas.

Padrão AWS para pods fora do espaço roteável: **`100.64.0.0/10` (CGNAT)** como **CIDR secundário**
da VPC + **custom networking** do VPC CNI. A mesma faixa pode ser repetida em todas as VPCs porque
nunca é anunciada para fora (TGW/peering roteiam só o CIDR primário).

Desenho proposto:

```
VPC primária  10.10.0.0/16    → nós, LBs, endpoints (como hoje)
VPC secundária 100.64.0.0/16  → pods
  100.64.0.0/18   pods AZ-a
  100.64.64.0/18  pods AZ-b
  100.64.128.0/18 pods AZ-c
```

Mudanças:
- `modules/vpc`: `aws_vpc_ipv4_cidr_block_association` + subnets de pods (sem rota de entrada
  externa; saída via NAT com SNAT no IP do nó).
- `modules/eks` (vpc-cni `configuration_values`): `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`,
  `ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone`; de preferência também `ENABLE_PREFIX_DELEGATION=true`.
- Um `ENIConfig` por AZ (subnet de pods + SG do cluster).
- Karpenter: com custom networking a ENI primária não leva pods, e o `maxPods` muda. Defina
  `kubelet.maxPods` no EC2NodeClass ou use prefix delegation.
- O Karpenter continua selecionando as **subnets de nós** (tag `karpenter.sh/discovery`). As subnets
  de pods **não** recebem essa tag.
- O ALB com `target-type: ip` continua funcionando: o CIDR secundário faz parte da VPC.
- Cartão: novo campo `pod_cidr` (validador: dentro de `100.64.0.0/10` ou `198.19.0.0/16`).

Com o Cilium em overlay (item 1), este item **não** é necessário.

## 3. DNS interno `brttech.cloud` (congelado)

> Congelado em 2026-11-22: é lab e o domínio não está registrado. Quando voltar, a opção mais
> barata é um subdomínio interno do `brttech.dev` (`*.int.dev.brttech.dev`): zona privada nas VPCs
> + ACM público validado pela zona pública existente, sem custo de certificado.

Objetivo: nomes privados para serviços internos (ex.: `api.dev.brttech.cloud`) resolvidos só dentro
das VPCs.

- **Route53 private hosted zone** `brttech.cloud` associada às VPCs dos clusters.
  - Multi-conta: a zona fica na conta **Network** e é associada às VPCs das outras contas
    (`aws_route53_vpc_association_authorization` + `aws_route53_zone_association`), ou via Route53 Profiles.
- **Segunda instância do external-dns** com `--aws-zone-type=private`, filtro
  `<environment>.brttech.cloud` e `txtOwnerId` próprio. A instância pública continua como está.
  - IAM com a mesma condição por subdomínio do external-dns público.
- **Ingress interno:** um Gateway com `LoadBalancerConfiguration` `scheme: internal` (o LBC já usa
  as subnets privadas `internal-elb`).
- **TLS:** ⚠️ um certificado ACM público para `*.dev.brttech.cloud` exige validação DNS **pública**.
  O domínio `brttech.cloud` precisa estar registrado e ter uma zona pública só para as validações.
  A alternativa é AWS Private CA, que custa ~US$400/mês por CA.
- Cartão (`account.yaml`): `internal_domain_name`, `internal_hosted_zone_id`.

## 4. KEDA, HPA e VPA

| Ferramenta | Situação | Plano |
|---|---|---|
| **HPA** | **já funciona** (metrics-server instalado) | documentar o padrão; requests obrigatórios (LimitRange dos tenants já aplica um default) |
| **KEDA** | — | Helm no pool `system`; Pod Identity para scalers AWS (SQS, CloudWatch, DynamoDB); flag `enable_keda` |
| **VPA** | — | Helm no pool `system`; começar com `updateMode: Off` (só recomendação) |

Estratégia (cada ferramenta responde a uma pergunta diferente):

| Camada | Pergunta | Sinal |
|---|---|---|
| KEDA (gera o HPA) | quantas réplicas? | requests no ALB (`RequestCountPerTarget`), fila SQS, cron; escala a zero |
| VPA | tamanho de cada pod? | histórico de CPU/memória |
| Karpenter | quantos nós? | pods pendentes |

1. **Um único dono das réplicas: o KEDA.** Nunca HPA manual + `ScaledObject` no mesmo Deployment;
   escala por CPU = trigger `cpu` dentro do `ScaledObject`.
2. **VPA `Initial` por padrão:** aplica requests só quando o pod nasce (inclusive os criados pelo
   KEDA), nunca despeja pod em execução.
3. **KEDA escalando por CPU ⇒ VPA não mexe em CPU** (`controlledResources: [memory]` ou `Off`).
4. **Limites:** VPA `minAllowed`/`maxAllowed`; KEDA `min/maxReplicaCount` + estabilização; PDB
   em todo workload com mais de uma réplica; `karpenter_limits` como teto de custo.
5. **Gradual:** 2 semanas com VPA `Off` (só recomendação), depois `Initial` workload a workload.

| Workload | Réplicas (KEDA) | Tamanho (VPA) |
|---|---|---|
| API HTTP | `RequestCountPerTarget` do ALB | `Initial`, CPU + memória |
| Worker de fila | profundidade SQS, até zero | `Initial`, CPU + memória |
| CPU-bound sem evento | trigger `cpu` | só memória, ou `Off` |
| Singleton / stateful | fixo | `InPlaceOrRecreate` + PDB |

O KEDA lê CloudWatch/SQS com Pod Identity, com role por squad (mesmo modelo do External Secrets).

## 5. GitOps

Mover os addons in-cluster (LBC, external-dns, ESO, KEDA, VPA, Cilium…) para Argo CD (self-managed ou
**EKS Capability**) com ApplicationSet por cluster. O Terraform fica com VPC, EKS, IAM e Pod
Identity associations. Ganhos: drift visível, destroy mais simples, sem providers k8s no Terraform.

## 6. Backlog de hardening

- NetworkPolicy **default-deny** por namespace de tenant (o CNI já suporta).
- Restringir `api_public_access_cidrs` (hoje `0.0.0.0/0`).
- Backup/DR: Velero ou AWS Backup para EKS + runbook de recriação.
- Policy engine (Kyverno): imagens de registries permitidos, requests obrigatórios, etc.
- Node auto-repair do Karpenter (o `eks-node-monitoring-agent` já publica as condições).
- CMK (KMS) para logs e secrets, se compliance exigir.
- Custo do lab: o pool `system` mantém 3× c6a.large (um por AZ por causa do spread). Avaliar um spread
  mais frouxo em dev.
- Limpar os órfãos do teste `eks-lab-dev` (4 roles IAM, log group, state no S3).
