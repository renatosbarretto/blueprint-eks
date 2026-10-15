# EKS Cluster Module

Provisiona cluster EKS com:
- KMS para criptografia etcd (secrets)
- Logging para CloudWatch (api, audit, authenticator, controller-manager, scheduler)
- IRSA (OIDC provider)
- Fargate profile para namespace do Karpenter
- Opção de criar KMS key para EBS

## Inputs

| Name | Description | Type |
|------|-------------|------|
| project_name | Project name | string |
| environment | Environment | string |
| cluster_version | Kubernetes version | string |
| vpc_id | VPC ID | string |
| private_subnet_ids | Private subnet IDs | list(string) |
| enable_irsa | Enable OIDC for IRSA | bool |
| create_fargate_profile_for_karpenter | Fargate profile for Karpenter | bool |
| karpenter_namespace | Karpenter namespace | string |
| create_ebs_kms_key | Create EBS KMS key | bool |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | EKS cluster name |
| cluster_arn | EKS cluster ARN |
| cluster_endpoint | API endpoint |
| cluster_certificate_data | CA certificate (sensitive) |
| oidc_provider_arn | OIDC provider ARN |
| ebs_kms_key_arn | EBS KMS key ARN (if created) |
