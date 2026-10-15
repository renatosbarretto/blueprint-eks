# VPC Module

VPC com subnets públicas e privadas em múltiplas AZs, NAT Gateways (um por AZ) e opção de VPC Flow Logs.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| project_name | Project name | string | required |
| environment | Environment | string | required |
| vpc_cidr | VPC CIDR | string | required |
| availability_zones | AZs | list(string) | required |
| public_subnet_cidrs | Public subnet CIDRs | list(string) | required |
| private_subnet_cidrs | Private subnet CIDRs | list(string) | required |
| enable_nat_gateway | NAT per AZ | bool | true |
| enable_flow_logs | VPC Flow Logs | bool | true |
| tags | Tags | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | VPC ID |
| vpc_cidr_block | VPC CIDR |
| public_subnet_ids | Public subnet IDs |
| private_subnet_ids | Private subnet IDs |
| nat_gateway_ips | NAT gateway public IPs |
