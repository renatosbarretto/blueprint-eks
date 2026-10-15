# IAM Identity Center Module

Configura acesso ao EKS via IAM Identity Center (SSO):

1. **EKS Access Entry** – associa o principal (role IAM criada pelo SSO) ao cluster.
2. **Access Policy** – associa `AmazonEKSClusterAdminPolicy` para acesso à API do cluster.
3. **RBAC** – ClusterRoleBinding que concede `cluster-admin` ao principal (role ARN como User no Kubernetes).

## Obtenção do principal_arn

Ao atribuir um Permission Set a um usuário/grupo na conta, o IAM Identity Center cria uma role IAM na conta. Use o ARN dessa role como `principal_arn`:

```bash
aws iam list-roles --query 'Roles[?starts_with(RoleName, `AWSReservedSSO`)].Arn' --output text
```

Ou no Console: IAM → Roles → filtrar por "AWSReservedSSO".

## Inputs

| Name | Description |
|------|-------------|
| cluster_name | Nome do cluster EKS |
| principal_arn | ARN da role IAM do SSO na conta |
| permission_set_arn | (Opcional) ARN do permission set, só referência |
| rbac_cluster_role_binding_name | Nome do ClusterRoleBinding (default: sso-cluster-admin) |

## Outputs

| Name | Description |
|------|-------------|
| access_entry_arn | Principal ARN do access entry |
| rbac_cluster_role_binding_name | Nome do ClusterRoleBinding |
