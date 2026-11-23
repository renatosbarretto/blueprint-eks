# Referência do cartão

Merge raso: `live/globals.yaml` (defaults) ← `account.yaml` ← `<cluster>.yaml`.
Mapas (ex.: `chart_versions`) são substituídos inteiros, não mesclados.

## Derivados do caminho

Não podem aparecer nos YAMLs (o validador acusa).

| Campo | Origem | Exemplo |
|---|---|---|
| `environment` | 1ª pasta (`dev`, `hml`, `prd`) | `dev` |
| `account_name` | 2ª pasta (DNS-1123) | `rb-lab-dev` |
| `cluster_name` | nome do arquivo (DNS-1123, ≤ 30) | `lab-dev` |

## `account.yaml`

| Chave | Obrigatória | Descrição |
|---|---|---|
| `account_id` | sim | 12 dígitos, entre aspas |
| `region` | sim | região dos clusters da conta |
| `availability_zones` | não | default `[us-east-1a, us-east-1b, us-east-1c]` |
| `domain_name` | se `enable_external_dns` | domínio público (ex.: `brttech.dev`) |
| `route53_hosted_zone_id` | se `enable_external_dns` | zona do domínio |
| `route53_assume_role_arn` | não | role na conta da zona (cross-account) |
| `access_entries` | não | admins da conta (cluster-scope) |
| `extra_tags` | não | tags adicionais |

Outras chaves no `account.yaml` geram erro: elas pertencem ao cluster.

## `<cluster>.yaml`: obrigatórias

| Chave | Exemplo | Observação |
|---|---|---|
| `vpc_cidr` | `10.10.0.0/16` | /16 a /18, sem sobreposição na conta |
| `cluster_version` | `"1.37"` | |
| `karpenter_version` | `"1.15.1"` | chart do Karpenter |
| `karpenter_ami_alias` | `al2023@v20261119` | `@latest` proibido em prd |
| `eks_addon_versions` | mapa addon → versão | obrigatório para todo addon habilitado |
| `chart_versions` | mapa chart → versão | obrigatório para todo chart habilitado |
| `gateway_api_version` | `v1.6.0` | precisa existir em `modules/gateway-api/crds/` |
| todos os `enable_*` | `true` / `false` | explícitos: o cartão mostra o que é e o que não é criado |

### `eks_addon_versions`

| Addon | Sempre? | Flag |
|---|---|---|
| `vpc-cni`, `kube-proxy`, `coredns`, `eks-pod-identity-agent` | sim | — |
| `aws-ebs-csi-driver` | não | `enable_ebs_csi` |
| `metrics-server` | não | `enable_metrics_server` |
| `eks-node-monitoring-agent` | não | `enable_node_monitoring_agent` |
| `amazon-cloudwatch-observability` | não | `enable_cloudwatch_observability` |

### `chart_versions`

| Chart | Flag |
|---|---|
| `aws_load_balancer_controller` | `enable_gateway_api` |
| `external_dns` | `enable_external_dns` |
| `external_secrets` | `enable_external_secrets` |
| `argocd` | `enable_argocd` |

## `enable_*`

| Flag | Cria |
|---|---|
| `enable_vpc` | VPC, subnets, NAT, endpoint S3 |
| `enable_breakglass_role` | role `<cluster>-eks-breakglass` (MFA) + access entry admin |
| `enable_network_policy` | NetworkPolicy no VPC CNI |
| `enable_flow_logs` | VPC Flow Logs no CloudWatch |
| `enable_eks` | cluster, Fargate profiles, addons core, OIDC (Karpenter) |
| `enable_karpenter` | controller, IAM, interrupção, NodePools `system`/`default` |
| `enable_eks_addons` | habilita a stack `eks-addons` |
| `enable_ebs_csi` | EBS CSI + StorageClass `gp3` default |
| `enable_metrics_server` | metrics-server (`kubectl top`, HPA) |
| `enable_node_monitoring_agent` | condições de saúde de nó |
| `enable_cloudwatch_observability` | Container Insights (custo por métrica/log) |
| `enable_tenants` | namespaces dos tenants |
| `enable_gateway_api` | LBC + CRDs + GatewayClasses |
| `enable_external_dns` | external-dns |
| `enable_external_secrets` | External Secrets + stores |
| `enable_argocd` | Argo CD |

## Opcionais (default em `globals.yaml`)

| Chave | Default | prd |
|---|---|---|
| `support_type` | `STANDARD` | |
| `deletion_protection` | `false` | **`true` obrigatório** |
| `api_public_access_cidrs` | `["0.0.0.0/0"]` | restringir |
| `cluster_log_retention_days` | 30 | 90 |
| `nat_gateway_mode` | `single` | **`per_az` obrigatório** |
| `vpc_interface_endpoints` | `[]` | `[ecr.api, ecr.dkr, sts, ec2, sqs]` |
| `flow_logs_retention_days` | 14 | 30 |
| `karpenter_replicas` | 1 | 2 |
| `karpenter_arch` | `[amd64]` | |
| `karpenter_capacity_types` | `[spot, on-demand]` | |
| `karpenter_limits` | `{cpu: "100", memory: 400Gi}` | |
| `tenants` | `[]` | |
| `access_entries` | — | extras cluster-scope |
| `extra_tags` | `{}` | |

## `tenants[]`

| Campo | Obrigatório | Regra |
|---|---|---|
| `name` | sim | DNS-1123, ≤ 20 chars |
| `namespaces` | sim | um namespace pertence a um só tenant |
| `sso_permission_set` / `principal_arn` | não (um ou outro) | sem eles: namespace + segredos, sem acesso EKS |
| `access_policy` | não | `view` / `edit` (default) / `admin` |
