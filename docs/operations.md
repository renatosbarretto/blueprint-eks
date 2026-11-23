# Operação

## Pré-requisitos

- Terraform ≥ 1.5 (testado com 1.15), Terragrunt 0.76, AWS CLI v2, kubectl, Python 3 com `pyyaml`.
- Sessão SSO na conta do cluster. Exemplo:

```bash
aws sso login --profile shadowops-dev-admin
export AWS_PROFILE=shadowops-dev-admin AWS_REGION=us-east-1
export TG_CLUSTER=lab-dev
```

Os scripts recusam rodar se `aws sts get-caller-identity` não for a conta do `account.yaml`.

## Ciclo de vida

### Validar

```bash
./scripts/validate-cluster.py                     # todos os cartões (CI roda isso)
./scripts/validate-cluster.py lab-dev --check-account
./scripts/validate-cluster.py lab-dev --get account_id   # lê um campo resolvido
```

### Criar / atualizar cluster

```bash
./scripts/bootstrap-state.sh        # 1x por conta: bucket de state
./scripts/apply-cluster.sh          # plan + confirmação stack a stack
./scripts/apply-cluster.sh --yes    # sem confirmação
```

Uma stack isolada: `cd live/stacks/<stack> && terragrunt plan`.

Tempos observados no lab-dev: vpc ~3 min, eks ~15 min, karpenter ~4 min (inclui o 1º nó),
eks-addons ~3 min, gateway-api ~2 min, external-dns ~4 min, external-secrets ~5 min.

### Destruir

```bash
./scripts/destroy-cluster.sh        # pede o nome do cluster
./scripts/destroy-cluster.sh --yes
```

O script:
1. remove Gateways, Ingress e Services `LoadBalancer` e espera o LBC apagar os ALB/NLB;
2. destrói as stacks em ordem inversa e **para no primeiro erro** (pode rodar de novo, é idempotente);
3. apaga LB/TG órfãos **só com a tag do cluster** e lista EC2 que ainda estejam com a tag.

Em prd, `deletion_protection: true` bloqueia o destroy do EKS. Desligue no cartão e aplique antes.

## Novo cluster

1. Copie um `<cluster>.yaml` para `live/clusters/<amb>/<conta>/` com o novo nome.
2. Escolha um `vpc_cidr` /16–/18 que não se sobreponha a outro da mesma conta.
3. `./scripts/validate-cluster.py <novo>` e `TG_CLUSTER=<novo> ./scripts/apply-cluster.sh`.

**Renomear um cluster = criar outro.** O state fica em `eks-blueprint/<cluster>/…`. Destrua o
antigo antes de renomear o arquivo.

## Nova conta

1. Crie `live/clusters/<amb>/<nome-da-conta>/account.yaml` (`account_id`, `region`,
   `availability_zones`, DNS).
2. Garanta que o permission set de admin exista na conta (`admins-production` hoje).
3. `TG_CLUSTER=<cluster> ./scripts/bootstrap-state.sh` (um bucket por conta).
4. `TG_CLUSTER=<cluster> ./scripts/bootstrap-github-oidc.sh` (OIDC do GitHub + roles do CI).
   Rode **antes** do primeiro apply: as access entries `gha-plan`/`gha-apply` do
   `globals.yaml` exigem que as roles existam.
5. Se a zona Route53 ficar em outra conta (ex.: Network), crie lá uma role para o external-dns e
   preencha `route53_assume_role_arn` no `account.yaml`.

## CI/CD (GitHub Actions)

| Workflow | Quando | O que faz |
|---|---|---|
| `ci.yml` | todo PR e push em main | valida cartões; fmt/validate/test por módulo; checkov |
| `terragrunt.yml` | PR em `live/` ou `modules/` | `plan` nos clusters afetados, um job por cluster |
| `terragrunt.yml` | manual (Run workflow + cluster) | `apply-cluster.sh --yes` de um cluster, após aprovação |

- **Sem segredos.** O job assume por OIDC `arn:aws:iam::<conta do cartão>:role/eks-blueprint-gha-plan`
  (pull_request, só leitura, sem ler segredos nem outros buckets) ou `…-gha-apply`.
- **Apply nunca é automático.** A role de apply só é assumível por job com GitHub Environment;
  cada cluster tem um Environment (`lab-dev`, …) com *Required reviewers* e branch restrita a `main`.
- **Cluster ainda não aplicado:** o plan cobre só a stack `vpc` e avisa — as demais dependem dos
  outputs dela, e mocks só valem em validate/destroy de propósito.
- Um apply por cluster por vez (`concurrency`); clusters diferentes rodam em paralelo.

## Tenants (squads)

```yaml
tenants:
  - name: payments                     # até 20 chars (vira nome de role IAM)
    namespaces: [payments]
    sso_permission_set: squad-payments # ou principal_arn
    access_policy: edit                # view | edit | admin
```

Aplique as stacks `eks` (access entry), `tenants` (namespace) e `external-secrets` (store + role).
Os segredos do tenant ficam em Secrets Manager como `<cluster>/payments/<nome>` e são usados com:

```yaml
secretStoreRef: { kind: ClusterSecretStore, name: tenant-payments }
```

## Upgrades

Sempre promova **dev → hml → prd**, mudando só o cartão.

### Versão do Kubernetes

1. Consulte as versões de addon compatíveis:
   ```bash
   for a in vpc-cni kube-proxy coredns eks-pod-identity-agent aws-ebs-csi-driver metrics-server eks-node-monitoring-agent; do
     aws eks describe-addon-versions --kubernetes-version <nova> --addon-name $a \
       --query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion|[0]' --output text
   done
   ```
2. No cartão: `cluster_version` e `eks_addon_versions`.
3. Aplique `eks` (control plane e addons core) e depois `eks-addons`.
4. Atualize `karpenter_ami_alias` para uma AMI da nova versão e aplique `karpenter`. O Karpenter
   detecta o drift e troca os nós respeitando os budgets (system: 1 nó por vez).

`support_type: STANDARD` faz a AWS forçar o upgrade no fim do suporte padrão em vez de cobrar
extended support (~6×). Não deixe a versão envelhecer.

### AMI dos nós

```bash
aws ssm get-parameter --name /aws/service/eks/optimized-ami/<versão>/amazon-linux-2023/x86_64/standard/recommended/image_id \
  --query Parameter.Value --output text | xargs -I{} aws ec2 describe-images --image-ids {} --query 'Images[0].Name' --output text
# amazon-eks-node-al2023-x86_64-standard-1.37-v20261119  →  karpenter_ami_alias: al2023@v20261119
```

`@latest` só é aceito fora de prd (o validador bloqueia em prd).

### Charts e CRDs

- Charts: `chart_versions` no cartão.
- CRDs do Gateway API / LBC: baixe a release nova para `modules/gateway-api/crds/` com o nome
  `gateway-api-<versão>-standard.yaml` / `lbc-v<versão>-gateway-crds.yaml` e ajuste
  `gateway_api_version` / `chart_versions.aws_load_balancer_controller`.

## Verificações rápidas

```bash
export KUBECONFIG=$(mktemp); aws eks update-kubeconfig --name $TG_CLUSTER
kubectl get nodeclaims -L karpenter.sh/nodepool,karpenter.sh/capacity-type
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl -n karpenter logs deploy/karpenter --since=10m | grep '"level":"ERROR"'
kubectl get gatewayclass,clustersecretstore
```

Smoke tests em `examples/`:
- `external-secrets/smoke.yaml`: tenant `echo` lê `lab-dev/echo/echo-smoke`;
- `gateway-api/echo-alb.yaml`: ALB público + `echo.dev.brttech.dev` (custa ~US$17/mês enquanto existir).

## Troubleshooting

Problemas já vistos no lab, com a causa e a correção:

| Sintoma | Causa | Correção |
|---|---|---|
| `ERRO: defina TG_CLUSTER` | variável não exportada | `export TG_CLUSTER=<cluster>` |
| `credenciais AWS são da conta X` | perfil errado (ex.: management) | `export AWS_PROFILE=<perfil da conta>` |
| `ResourceAlreadyExistsException` no log group do EKS | log group de um cluster anterior com o mesmo nome | `terragrunt import aws_cloudwatch_log_group.cluster /aws/eks/<cluster>/cluster` na stack `eks` |
| Terragrunt pergunta se pode atualizar o bucket | o bucket tem a policy do `bootstrap-state.sh` | já tratado com `disable_bucket_update = true` |
| external-dns: `InvalidChangeBatch … already exists` em TXT `cname-*` | TXT de controle órfão de um cluster anterior | apague só esse TXT (confira `external-dns/owner=`) |
| Karpenter: `AccessDenied GetInstanceProfile` em `/karpenter/<região>/<cluster>/…` | instance profile órfão criado por um Karpenter antigo | `aws iam delete-instance-profile` no órfão (sem roles) |
| Nó não fica Ready | vpc-cni sem credenciais ou sem access entry do nó | `kubectl -n kube-system logs ds/aws-node`; confira `aws_eks_access_entry.nodes` |
| ALB `internal-*` em vez de público | falta `LoadBalancerConfiguration` com `scheme: internet-facing` | ver `examples/gateway-api/echo-alb.yaml` |

## Custos de referência (lab-dev, us-east-1)

| Item | ~US$/mês |
|---|---|
| Control plane EKS | 73 |
| Fargate (Karpenter + 2× CoreDNS) | 55 |
| 3× c6a.large on-demand (pool system) | 170 |
| NAT single | 33 + tráfego |
| ALB do smoke test | 17 |
| Spot (workloads) | conforme uso |

prd adiciona NAT por AZ (3×), interface endpoints (~US$7 por serviço por AZ), flow logs e 2 réplicas do Karpenter.
