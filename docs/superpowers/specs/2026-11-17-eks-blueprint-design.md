# Design: EKS Blueprint (Terragrunt + multi-env)

**Date:** 2026-11-17  
**Status:** Approved — implementation in progress  
**Account (lab):** RB-LAB-DEV `280912093812`  
**Region:** `us-east-1`

## 1. Purpose

Rebuild the EKS blueprint from scratch as a **lab-first platform** with a clear path to production.

- **V1:** Full platform stacks in one AWS account, three isolated VPCs (`dev` / `hml` / `prd`).
- **V2:** Insert account folders and real multi-account wiring without rewriting modules.
- **Operator UX:** Creating/changing a cluster means editing **one** env file (identity + feature flags `true`/`false`).

## 2. Goals and non-goals

### Goals

- Terragrunt orchestrates Terraform; shared modules under `modules/`.
- Layout by environment first; account layer later.
- Feature flags for VPC, EKS, Karpenter, add-ons, ArgoCD, Gateway API, ExternalDNS.
- Karpenter + CoreDNS on Fargate; all other workloads on Karpenter nodes.
- EKS Access Entry for a global SSO admin role on every cluster.
- Route53 zone `brttech.dev` prepared for ExternalDNS (disabled by default).

### Non-goals (V1)

- Real multi-account deployment (structure only documented).
- Secondary CIDR / VPC CNI custom networking.
- Existing-VPC import mode.
- Full LGTM / observability stack.
- Overwriting apex/`www` DNS (CloudFront-owned).

## 3. Architecture

### Approach

**Terragrunt per environment + per stack** (chosen):

```
modules/{vpc,eks,...}/
live/
  root.hcl                         # loads clusters/${TG_CLUSTER}/cluster.hcl
  clusters/<cluster-id>/cluster.hcl  # ONLY operator surface (name, version, access entries, flags)
  stacks/{vpc,eks,...}/terragrunt.hcl
```

- Primary UX object: **cluster card** (`cluster.hcl`) — name, version, account, VPC, squad Access Entries, feature flags.
- Lab now: multiple cluster cards in one account (one VPC each). Future: one cluster per AWS account via `account_id` (optional path split later).
- Select with `TG_CLUSTER=lab-dev` (default). State key: `eks-blueprint/{cluster_name}/{stack}/`.
- Gitflow: config PRs → `live/clusters/*/cluster.hcl`; platform PRs → `live/stacks/` or `modules/`.


### Dependency order

```
vpc → eks → eks-addons → karpenter → gateway-api → external-dns → argocd
```

Stacks with `enable_* = false` are skipped (Terragrunt skip / conditional apply).

## 4. Operator UX — single env file

Example: `live/dev/env.hcl`

```hcl
account_id  = "280912093812"
region      = "us-east-1"
environment = "dev"
project     = "eks-blueprint"
vpc_cidr    = "10.10.0.0/20"

domain_name            = "brttech.dev"
route53_hosted_zone_id = "Z09087232IC05YG46FH45"

eks_admin_principal_arns = [
  "arn:aws:iam::280912093812:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_admins-production_6c3685c940f969f5"
]

enable_vpc            = true
enable_eks            = true
enable_karpenter      = true
enable_eks_addons     = true
enable_vpc_cni        = true
enable_coredns        = true
enable_kube_proxy     = true
enable_ebs_csi        = true
enable_metrics_server = true
enable_argocd         = false   # operator choice
enable_gateway_api    = false   # V1 first apply
enable_external_dns   = false   # V1 first apply
```

**New cluster / env:** copy `live/dev` → adjust `env.hcl` (CIDR + flags) → `terragrunt run-all apply`.

## 5. Network

| Env | VPC CIDR | AZs | Subnets | NAT |
|-----|----------|-----|---------|-----|
| `dev` | `10.10.0.0/20` | 3 | 3 public + 3 private (`/24`) | 1 per VPC |
| `hml` | `10.20.0.0/20` | 3 | same pattern | 1 |
| `prd` | `10.30.0.0/20` | 3 | same pattern | 1 |

**Tags (module responsibility):**

- Public: `kubernetes.io/role/elb = 1`
- Private: `kubernetes.io/role/internal-elb = 1`
- Both: `kubernetes.io/cluster/<project>-<environment> = shared`

No secondary CIDR / custom networking in V1.

## 6. EKS and compute

- Cluster name: `${project}-${environment}` (e.g. `eks-blueprint-dev`).
- Kubernetes version: pin a current stable in implementation plan (target ≥ 1.31).
- Endpoint: public + private (lab).
- Authentication: **API** mode (Access Entries only).

### Access Entry

For every cluster, create Access Entry + `AmazonEKSClusterAdminPolicy` (cluster scope) for:

`arn:aws:iam::280912093812:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_admins-production_6c3685c940f969f5`

Configurable via `eks_admin_principal_arns` in `env.hcl` (intended as global admin across future accounts/clusters).

### Compute placement

| Workload | Placement |
|----------|-----------|
| Karpenter controller | Fargate |
| CoreDNS | Fargate (`computeType = Fargate`) |
| Everything else | Karpenter-provisioned nodes |

- No managed node group in V1.
- Fargate profiles: `karpenter` namespace + `kube-system` (CoreDNS).

### Add-ons (flagged)

`vpc-cni`, `coredns`, `kube-proxy`, `ebs-csi`, `metrics-server` — each toggleable; defaults `true` unless operator sets `false`.

## 7. GitOps, Gateway API, ExternalDNS

### ArgoCD (`enable_argocd`)

- Helm install into `argocd` namespace.
- Initial access via port-forward until ingress/DNS enabled.
- V1 may install controller only (sample Applications optional).

### Gateway API (`enable_gateway_api`, default `false`)

- AWS Load Balancer Controller + Gateway API CRDs.
- Uses VPC subnet tags for discovery.

### ExternalDNS (`enable_external_dns`, default `false`)

- Hosted zone: `brttech.dev` / `Z09087232IC05YG46FH45`.
- DNS names: `{service}.{environment}.brttech.dev` (e.g. `argocd.dev.brttech.dev`).
- **Must not** manage apex or `www` (existing CloudFront aliases).
- IRSA + IAM policy scoped to that hosted zone only.

## 8. Remote state and auth

- S3 + DynamoDB lock in account `280912093812`.
- State key pattern: `eks-blueprint/{env}/{stack}/terraform.tfstate`.
- Bootstrap bucket/table once (script or documented manual step).
- Lab auth: AWS SSO / local profile to `280912093812`.
- CI OIDC (GitHub Actions) deferred to V2 path; design compatible.

## 9. Multi-account path (V2 — documented only)

```
live/{env}/{account-name}/{stack}/
```

Today:

```
live/{env}/{stack}/
```

- Modules stay unchanged.
- `env.hcl` / future `account.hcl` split platform vs account identity.
- Same feature-flag UX.

## 10. Success criteria

- [ ] `terragrunt run-all plan` works for `dev` with flags as designed.
- [ ] Three VPCs can be applied independently with non-overlapping CIDRs.
- [ ] EKS + Karpenter + CoreDNS-on-Fargate come up; workloads schedule on Karpenter nodes.
- [ ] SSO admin role can `kubectl` via Access Entry.
- [ ] With `enable_gateway_api` / `enable_external_dns` / `enable_argocd` = `false`, those stacks are skipped.
- [ ] Flipping flags to `true` and re-applying installs the corresponding components without redesign.
- [ ] README documents: copy env, edit `env.hcl`, apply order, destroy notes.

## 11. Open decisions for implementation plan

- Exact Kubernetes and Karpenter chart versions.
- Exact `/24` subnet math per VPC (derive from `vpc_cidr` in module).
- Whether ArgoCD default in sample `env.hcl` is `false` or `true` (operator preference; design supports both).
- Bootstrap automation for S3/DynamoDB vs manual once.

## 12. Out of scope reminders

- Homelab / Proxmox.
- Observability (LGTM) as required V1 deliverable.
- Account-per-environment AWS Organizations automation.
