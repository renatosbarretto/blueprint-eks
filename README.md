# EKS Blueprint

Terragrunt + Terraform — **um arquivo = um cluster**.

```
live/
  globals.yaml              ← defaults de todos os clusters + access entries globais
  clusters/                 ← VOCÊ trabalha aqui
    <ambiente>/             ← dev | hml | prd  (vira o environment)
      <conta>/              ← nome da conta AWS
        account.yaml        ← account_id, região, AZs, DNS, access entries da conta
        <cluster>.yaml      ← cartão do cluster (nome do arquivo = cluster_name)
  stacks/                   ← wiring Terragrunt (raramente mexer)
  _common/k8s.hcl           ← providers kubernetes/helm/kubectl compartilhados
  root.hcl
modules/                    ← código Terraform (com tests/ onde há lógica)
scripts/                    ← validate / bootstrap / apply / destroy
```

| Camada | Quem edita | Quando |
|--------|------------|--------|
| `clusters/<amb>/<conta>/account.yaml` | platform | conta nova, DNS da conta |
| `clusters/<amb>/<conta>/<cluster>.yaml` | você / PR | novo cluster, versões, componentes, tenants |
| `globals.yaml` | platform | defaults, admins globais |
| `stacks/`, `modules/` | platform | wiring e recursos |

Documentação completa: [docs/](docs/README.md) (arquitetura, operação, segurança, referência do cartão, decisões, roadmap).

## Uso

```bash
export TG_CLUSTER=lab-dev                 # nome do cluster (obrigatório, sem default)

./scripts/validate-cluster.py             # valida todos os cartões (CI roda isso)
./scripts/bootstrap-state.sh              # bucket de state na conta do cartão (1x por conta)
./scripts/apply-cluster.sh                # apply sequencial (plan + confirmação por stack)
./scripts/apply-cluster.sh --yes          # sem confirmação
./scripts/destroy-cluster.sh              # pede o nome do cluster para confirmar
```

Todos os scripts conferem se as **credenciais AWS são da conta do cartão**; o provider gerado também tem `allowed_account_ids`.

Stack isolada: `cd live/stacks/<stack> && terragrunt plan`.

## Ordem de bootstrap

```
vpc → eks → karpenter → eks-addons → tenants → gateway-api → external-dns → external-secrets → argocd
```

- **eks** cria cluster + Fargate (CoreDNS e Karpenter) + addons que não precisam de nó EC2:
  `vpc-cni`, `kube-proxy`, `coredns` (Fargate), `eks-pod-identity-agent`.
- **karpenter** sobe o controller no Fargate, cria os NodePools `system` (on-demand, taint
  `CriticalAddonsOnly`) e `default` (spot + on-demand), e espera 1 nó `system` Ready.
- O resto roda em nós EC2. Componentes de plataforma vão para o pool `system`.

## Cartão do cluster

Merge: `globals.yaml` (defaults) ← `account.yaml` ← `<cluster>.yaml`.
`cluster_name`, `environment` e `account_name` vêm do caminho — não aparecem nos YAMLs.

O cartão do cluster declara **explicitamente** versões (cluster, Karpenter, AMI, cada addon EKS,
charts) e todos os `enable_*`: lendo o arquivo você sabe o que é e o que não é criado.
O validador falha se faltar versão de addon/chart habilitado, flag não declarada ou chave desconhecida.

Hoje (lab) os três ambientes simulam contas com VPCs na mesma conta (`*/rb-lab-dev/`, conta RB-LAB-DEV). Com contas
reais: renomeie a pasta da conta e troque o `account_id` no `account.yaml`.

### Tenants (squads)

```yaml
tenants:
  - name: payments
    namespaces: [payments, payments-jobs]
    sso_permission_set: squad-payments   # ou principal_arn
    access_policy: edit                  # view | edit | admin
```

Cada tenant ganha:
- namespaces com Pod Security (`enforce: baseline`, `warn/audit: restricted`) e LimitRange default;
- Access Entry **com escopo nos seus namespaces** (não no cluster);
- `ClusterSecretStore tenant-<name>` que só lê `<cluster>/<name>/*` no Secrets Manager
  e só pode ser usado nos namespaces do tenant.

Segredos de plataforma: `<cluster>/platform/*` via store `platform`.

### Acesso

- Admins globais em `globals.yaml` (`access_entries`).
- Role **break-glass** `<cluster>-eks-breakglass` (exige MFA) para quando o SSO falhar.
- Role do CI/CD que roda Terraform precisa de access entry (exemplo comentado em `globals.yaml`).

## Testes

```bash
cd modules/vpc && terraform init -backend=false && terraform test
```

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)): validador de cartões, `fmt`, `validate`,
`terraform test` por módulo e checkov.
