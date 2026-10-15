# Secondary Network Module

Associa um bloco CIDR secundário à VPC (ex.: 10.147.0.0/16) e opcionalmente cria subnets e route table. O roteamento entre 10.147.x e 10.0.x é local na VPC após a associação.

## Inputs

| Name | Description | Type |
|------|-------------|------|
| vpc_id | VPC ID | string |
| secondary_cidr | CIDR secundário | string |
| availability_zones | AZs | list(string) |
| create_secondary_subnets | Criar subnets no CIDR secundário | bool |
| tags | Tags | map(string) |

## Outputs

| Name | Description |
|------|-------------|
| secondary_cidr_association_id | ID da associação do CIDR |
| secondary_route_table_id | Route table das subnets secundárias |
