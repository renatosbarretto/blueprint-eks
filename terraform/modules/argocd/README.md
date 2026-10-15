# ArgoCD Module

Instala o ArgoCD via Helm para fluxo GitOps.

## Inputs

| Name | Description |
|------|-------------|
| cluster_name | Nome do cluster (dependency) |
| namespace | Namespace (default: argocd) |
| argocd_version | Versão do chart (ex.: 6.0.0) |
| helm_values | Valores adicionais Helm |

## Outputs

| Name | Description |
|------|-------------|
| argocd_endpoint | URL do server (cluster-local) |
| argocd_admin_username | Usuário admin (admin) |

## Importar release já instalado

Se o ArgoCD já estiver rodando no cluster (instalação anterior ou manual) e o Terraform falhar com "cannot re-use a name that is still in use", importe o release para o state a partir do diretório **terraform**:

```bash
terraform import 'module.argocd[0].helm_release.argocd' argocd/argocd
```

Depois rode `terraform plan`; se aparecer diff em `values`, ajuste `helm_values` no root para refletir o que está no cluster ou aceite o update.
