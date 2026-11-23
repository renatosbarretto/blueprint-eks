# Clusters

```
<ambiente>/<conta>/account.yaml     ← conta: account_id, região, AZs, DNS
<ambiente>/<conta>/<cluster>.yaml   ← cluster (nome do arquivo = cluster_name)
```

```bash
export TG_CLUSTER=lab-dev                       # nome do cluster
../../scripts/validate-cluster.py "$TG_CLUSTER"
../../scripts/validate-cluster.py "$TG_CLUSTER" --get account_id   # campo resolvido
```

**Novo cluster:** copie um `<cluster>.yaml` para a pasta da conta, renomeie o arquivo e use um
`vpc_cidr` que não se sobreponha aos outros da mesma conta (o validador confere).

**Nova conta:** crie `<ambiente>/<nome-da-conta>/account.yaml` e rode `scripts/bootstrap-state.sh`
(um bucket de state por conta).

**Renomear cluster = cluster novo** (state em `eks-blueprint/<cluster>/...`). Destrua o antigo antes.
