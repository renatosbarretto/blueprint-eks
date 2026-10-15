# Gateway API Module

Instala Gateway API CRDs e o AWS Load Balancer Controller para integrar com ALB/NLB e HTTPRoute.

## Inputs

| Name | Description |
|------|-------------|
| cluster_name | Nome do cluster EKS |
| oidc_provider_arn | ARN do OIDC provider |
| vpc_id | VPC ID |
| gateway_api_version | Versão do chart gateway-api-crds |

## Outputs

| Name | Description |
|------|-------------|
| gateway_api_namespace | Namespace gateway-api-system |
| controller_role_arn | ARN da role do controller |
