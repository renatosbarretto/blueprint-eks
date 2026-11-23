# Documentação do EKS Blueprint

Blueprint Terragrunt + Terraform para clusters EKS. Cada cluster é descrito por um arquivo YAML
(o "cartão") e recebe o mesmo conjunto de componentes de plataforma: rede, control plane, Karpenter,
addons, isolamento de tenants, ingress via Gateway API, DNS e segredos.

| Documento | Para quem | Conteúdo |
|---|---|---|
| [Arquitetura](architecture.md) | todos | visão geral, componentes, ordem de bootstrap, rede, compute |
| [Operação](operations.md) | quem opera | criar/destruir cluster, upgrades, tenants, troubleshooting |
| [Segurança](security.md) | platform / segurança | IAM, identidade de workloads, acesso, isolamento de tenants |
| [Referência do cartão](card-reference.md) | quem cria cluster | todas as chaves do YAML, defaults e validações |
| [Decisões](decisions.md) | platform | por que cada escolha foi feita (ADRs curtos) |
| [Roadmap](roadmap.md) | platform | próximos módulos e cuidados de design |

Começo rápido: [README da raiz](../README.md).

> `superpowers/` guarda a especificação e o plano originais (2026-11-17). São históricos e foram
> superados por estes documentos.

## Estado atual

| Cluster | Ambiente | Conta | Status |
|---|---|---|---|
| `lab-dev` | dev | RB-LAB-DEV (280912093812) | **em execução** |
| `lab-hml` | hml | RB-LAB-DEV (280912093812) | cartão pronto, não aplicado |
| `lab-prd` | prd | RB-LAB-DEV (280912093812) | cartão pronto, não aplicado |

Hoje os ambientes simulam contas separadas usando VPCs na mesma conta. O layout de pastas já está
pronto para uma conta por ambiente (ver [Operação → Nova conta](operations.md#nova-conta)).
