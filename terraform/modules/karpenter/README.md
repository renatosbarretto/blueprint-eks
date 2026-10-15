# Karpenter Module

Instala o Karpenter para auto-scaling de nodes no EKS.

- **Controller** roda no Fargate (namespace com Fargate profile no módulo eks-cluster).
- **IRSA** para o controller acessar APIs AWS (EC2, IAM, EKS, SQS, Pricing).
- **Node IAM role + instance profile** para os nodes provisionados pelo Karpenter.
- **EKS Access Entry** para o node role poder ingressar no cluster.

Requer que o cluster EKS, OIDC e o Fargate profile do namespace já existam.

## Inputs

| Name | Description |
|------|-------------|
| cluster_name | Nome do cluster EKS |
| cluster_endpoint | Endpoint do cluster |
| oidc_provider_arn | ARN do OIDC provider |
| namespace | Namespace do Karpenter (deve ter Fargate profile) |
| karpenter_version | Versão do Helm chart (ex.: v0.32.0) |

## Outputs

| Name | Description |
|------|-------------|
| karpenter_role_arn | ARN da role IRSA do controller |
| node_instance_profile_name | Nome do instance profile dos nodes |
