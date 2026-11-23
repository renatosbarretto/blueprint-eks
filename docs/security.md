# Segurança

## Proteções contra erro de operação

| Risco | Proteção |
|---|---|
| Esquecer `TG_CLUSTER` e aplicar no cluster errado | `TG_CLUSTER` obrigatório, sem default |
| Credenciais da conta errada | `allowed_account_ids` no provider + `validate-cluster.py --check-account` nos scripts |
| Typo ou chave faltando no cartão | validador falha com chave desconhecida, versão de addon/chart faltando ou flag não declarada |
| CIDRs sobrepostos na mesma conta | validador compara as VPCs da conta |
| Destruir prd por engano | `deletion_protection` (obrigatório em prd) + `destroy-cluster.sh` pede o nome do cluster |
| Destroy apagar recursos de outro cluster | limpeza de LB/TG só por tag `elbv2.k8s.aws/cluster=<cluster>` |

## Acesso ao cluster

`authentication_mode = API` (sem `aws-auth`). `bootstrap_cluster_creator_admin_permissions = false`:
quem rodou o Terraform **não** vira admin implicitamente.

| Quem | Como | Escopo |
|---|---|---|
| Admins (SSO `admins-production`) | `globals.yaml` → `access_entries` | cluster |
| Extras da conta/cluster | `account.yaml` / `<cluster>.yaml` → `access_entries` | cluster |
| Squads | `tenants[].sso_permission_set` ou `principal_arn` | **namespaces do tenant** |
| Break-glass | role `<cluster>-eks-breakglass` (assumível na conta **com MFA**) | cluster |
| Nós Karpenter | access entry `EC2_LINUX` da role de nó | — |

`sso_permission_set` é resolvido na conta (`AWSReservedSSO_<set>_*`). Isso evita fixar o sufixo
aleatório da role SSO.

> A role de CI/CD que roda Terraform precisa de uma access entry (exemplo comentado em `globals.yaml`).

## Identidade dos workloads

Padrão: **EKS Pod Identity**. Uma trust policy (`pods.eks.amazonaws.com` com
`aws:SourceAccount`) é reutilizável entre clusters, sem OIDC por cluster.

| Workload | Mecanismo | Permissões |
|---|---|---|
| vpc-cni (`aws-node`) | Pod Identity | `AmazonEKS_CNI_Policy` |
| EBS CSI | Pod Identity | `AmazonEBSCSIDriverPolicy` |
| LBC | Pod Identity | policy oficial do LBC (`modules/gateway-api/iam-policy.json`) |
| external-dns | Pod Identity | Route53 só em `<env>.<domain>` |
| External Secrets | Pod Identity | `platform/*` + `sts:AssumeRole` nas roles de tenant |
| Karpenter | **IRSA** | ver abaixo |

A role de nó **não** tem `AmazonEKS_CNI_Policy`: só `WorkerNode`, `ECR ReadOnly` e `SSM`.
Com IMDSv2 e hop limit 1, os pods não conseguem usar as credenciais do nó.

### Karpenter

Exceção ao Pod Identity porque o controller roda no Fargate. A policy segue a oficial v1, com
escopo por cluster:

- `RunInstances`/`CreateFleet`/`CreateLaunchTemplate` exigem as tags
  `kubernetes.io/cluster/<cluster>=owned` e `eks:eks-cluster-name=<cluster>` na requisição;
- `TerminateInstances`/`DeleteLaunchTemplate` só em recursos com essa tag;
- `iam:PassRole` **só da role de nó deste cluster**, e só para `ec2.amazonaws.com`;
- sem `iam:CreateInstanceProfile`/`AddRoleToInstanceProfile`: o instance profile é do Terraform.
  Fica apenas `GetInstanceProfile` (o profile do cluster) e `ListInstanceProfiles` (path do cluster, para o GC);
- leituras de EC2 restritas à região do cluster;
- SQS só na fila do cluster.

Por isso o Karpenter de um cluster **não** consegue terminar nós de outro cluster na mesma conta
nem escalar privilégio passando outra role.

Teste automatizado: `modules/karpenter/tests/iam_scope.tftest.hcl`.

## Isolamento de tenants

Um tenant (`tenants:` no cartão) ganha:

| Camada | Controle |
|---|---|
| Kubernetes RBAC | access policy (`view`/`edit`/`admin`) **com escopo de namespace** |
| Pod Security | `enforce: baseline`, `warn`/`audit: restricted` |
| Recursos | LimitRange com requests default (100m / 128Mi) e limite de memória (512Mi) |
| Segredos | `ClusterSecretStore tenant-<name>` com `conditions.namespaces` = namespaces do tenant, assumindo a role `<cluster>-eso-<tenant>`, que só lê `<cluster>/<tenant>/*` |

Validado no lab: um `ExternalSecret` no namespace `default` apontando para `tenant-echo` é recusado
(`SecretSyncedError`), e nenhum Secret é criado.

Ainda **não** existe NetworkPolicy default-deny por tenant (o CNI já suporta). Ver [Roadmap](roadmap.md).

## Dados e logs

| Item | Configuração |
|---|---|
| Logs do control plane | `api`, `audit`, `authenticator`; retenção do cartão (30d dev, 90d prd) |
| Secrets do Kubernetes | envelope encryption default do EKS (chave AWS). CMK é decisão de compliance |
| Volumes EBS | StorageClass `gp3` com `encrypted: true`; root dos nós criptografado |
| State do Terraform | S3 versionado, SSE, bloqueio público, **nega HTTP sem TLS**, versões antigas expiram em 90 dias |
| SQS de interrupção | SSE gerenciado + nega HTTP sem TLS |
| Endpoint da API | público restrito a `api_public_access_cidrs` + privado. **Hoje `0.0.0.0/0`: restringir** |

## Exceções do checkov

Ficam no código, com justificativa (`checkov:skip=`):

| Check | Motivo |
|---|---|
| CKV_AWS_58 (secrets encryption) | envelope encryption default do EKS; CMK opcional |
| CKV_AWS_37 (todos os log types) | controllerManager/scheduler fora por custo |
| CKV_AWS_158 / 338 (log group KMS / 1 ano) | retenção vem do cartão; CMK por compliance |
| CKV2_AWS_5 (SG endpoints) | anexado via `for_each` |
| CKV_K8S_8/9/15/43 (pod de piso) | `pause` não serve tráfego; tag imutável |
