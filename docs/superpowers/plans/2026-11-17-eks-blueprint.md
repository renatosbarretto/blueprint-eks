# EKS Blueprint (Terragrunt) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold and implement a Terragrunt-orchestrated EKS platform with three env VPCs, feature-flagged stacks, and a single `env.hcl` operator file.

**Architecture:** Shared Terraform modules under `modules/`; live composition under `live/{dev,hml,prd}/{stack}` with Terragrunt dependencies. Lab runs all envs in account `280912093812`. Stacks skip when their `enable_*` flag is false.

**Tech Stack:** Terraform ≥ 1.5, Terragrunt ≥ 0.55, AWS provider ~> 5.0, Helm/Kubernetes providers where needed, Karpenter on Fargate, EKS Access Entries (API auth mode).

**Spec:** `docs/superpowers/specs/2026-11-17-eks-blueprint-design.md`

## Global Constraints

- Account (lab): `280912093812` · Region: `us-east-1`
- Envs: `dev` (`10.10.0.0/20`), `hml` (`10.20.0.0/20`), `prd` (`10.30.0.0/20`)
- 3 AZs, 3 public + 3 private `/24`, 1 NAT per VPC
- Cluster name: `${project}-${environment}`
- Kubernetes version pin for V1: `1.31`
- Karpenter Helm chart pin: `1.1.1` (adjust only if chart requires K8s 1.31 compatibility; document if bumped)
- SSO admin ARN (Access Entry on every cluster): `arn:aws:iam::280912093812:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_admins-production_6c3685c940f969f5`
- Domain: `brttech.dev` · Zone: `Z09087232IC05YG46FH45` · ExternalDNS must not manage apex/`www`
- Default flags in sample `env.hcl`: `enable_gateway_api = false`, `enable_external_dns = false`, `enable_argocd = false`
- State key: `eks-blueprint/{env}/{stack}/terraform.tfstate`
- No secondary CIDR / custom networking / managed node groups in V1

## Review Focus

- Overlapping or invalid subnet CIDRs derived from `vpc_cidr` — expect non-overlapping `/24`s inside the `/20`
- `enable_* = false` still creating resources — expect stack skipped (no apply of that module)
- Access Entry missing SSO ARN — expect `kubectl` with SSO role fails; with entry succeeds
- ExternalDNS when enabled touching apex/`www` — expect only `{service}.{env}.brttech.dev` domain filter
- Karpenter/CoreDNS not on Fargate — expect Fargate profiles + CoreDNS `computeType=Fargate`; other pods on Karpenter nodes

## File map

| Path | Responsibility |
|------|----------------|
| `live/root.hcl` | Remote state, provider generate, common tags |
| `live/{env}/env.hcl` | Single operator inputs + flags |
| `live/{env}/{stack}/terragrunt.hcl` | Module source, inputs, deps, skip |
| `modules/vpc` | VPC, subnets, IGW, NAT, routes, EKS tags |
| `modules/eks` | Cluster, OIDC, Fargate profiles, Access Entries |
| `modules/eks-addons` | vpc-cni, coredns, kube-proxy, ebs-csi, metrics-server |
| `modules/karpenter` | IRSA, Helm, interruption queue, NodePool/EC2NodeClass |
| `modules/gateway-api` | LBC + Gateway API (flagged) |
| `modules/external-dns` | Helm + IRSA Route53 (flagged) |
| `modules/argocd` | Helm ArgoCD (flagged) |
| `scripts/bootstrap-state.sh` | Create S3 + DynamoDB for state |
| `README.md` | Copy env, edit flags, apply/destroy |

---

### Task 1: Repo scaffold + Terragrunt root + env templates

**Files:**
- Create: `live/root.hcl`
- Create: `live/dev/env.hcl`, `live/hml/env.hcl`, `live/prd/env.hcl`
- Create: `scripts/bootstrap-state.sh`
- Modify: `README.md` (bootstrap + how to apply)
- Test: `scripts/check-env-hcl.sh` (or inline assertions in bootstrap dry-run)

**Interfaces:**
- Produces: `locals` shape in `env.hcl` consumed by all stacks: `account_id`, `region`, `environment`, `project`, `vpc_cidr`, `domain_name`, `route53_hosted_zone_id`, `eks_admin_principal_arns`, all `enable_*` bools
- Produces: `root.hcl` remote_state config with key `eks-blueprint/${env}/${stack}/terraform.tfstate`

- [ ] **Step 1: Write failing check that required env keys exist**

Create `scripts/check-env-hcl.sh` that fails if `live/dev/env.hcl` missing keys: `account_id`, `vpc_cidr`, `enable_vpc`, `enable_gateway_api`, `enable_external_dns`, `enable_argocd`.

- [ ] **Step 2: Run check — expect FAIL (files missing)**

Run: `bash scripts/check-env-hcl.sh`  
Expected: FAIL / file not found

- [ ] **Step 3: Implement `live/root.hcl` + three `env.hcl` with spec values**

`dev` CIDR `10.10.0.0/20`, `hml` `10.20.0.0/20`, `prd` `10.30.0.0/20`; account `280912093812`; gateway/external-dns/argocd `false`.

- [ ] **Step 4: Implement `scripts/bootstrap-state.sh`**

Creates bucket + DynamoDB table names documented in README (exact names chosen once, e.g. `eks-blueprint-tfstate-280912093812` and `eks-blueprint-tflock`).

- [ ] **Step 5: Re-run check — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add live scripts README.md
git commit -m "chore: scaffold Terragrunt root and env.hcl templates"
```

---

### Task 2: VPC module + live stacks (dev/hml/prd)

**Files:**
- Create: `modules/vpc/{main.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/vpc/terragrunt.hcl`
- Test: `modules/vpc/tests` or `terraform -chdir=modules/vpc validate` + CIDR unit via `terraform console` / small script

**Interfaces:**
- Consumes: `project`, `environment`, `vpc_cidr`, `availability_zones` (default 3 in region), `single_nat_gateway=true`, `tags`
- Produces outputs: `vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_ips`, `azs`
- Subnet derivation: from `vpc_cidr` `/20`, allocate 3 public then 3 private consecutive `/24`s
- Tags: public `kubernetes.io/role/elb=1`; private `kubernetes.io/role/internal-elb=1`; both `kubernetes.io/cluster/${project}-${environment}=shared`

- [ ] **Step 1: Write failing test for subnet CIDR derivation**

Assert for `10.10.0.0/20` → public `10.10.0.0/24`,`10.10.1.0/24`,`10.10.2.0/24` and private `10.10.3.0/24`,`10.10.4.0/24`,`10.10.5.0/24` (or document chosen offset if private starts at `.10` — **pin one scheme in module locals and mirror in test**).

Pinned scheme for this plan:
- public index `0..2` → `cidrsubnet(vpc_cidr, 4, i)`
- private index `0..2` → `cidrsubnet(vpc_cidr, 4, i+3)`

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement `modules/vpc`**

- [ ] **Step 4: Add `live/*/vpc/terragrunt.hcl` with `skip = !enable_vpc`**

- [ ] **Step 5: `terragrunt validate` in `live/dev/vpc` (after bootstrap/init) — expect OK**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: add VPC module and live stacks for dev/hml/prd"
```

---

### Task 3: EKS module (cluster, Fargate profiles, Access Entries)

**Files:**
- Create: `modules/eks/{main.tf,iam.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/eks/terragrunt.hcl`
- Test: `terraform validate`; document manual Access Entry check

**Interfaces:**
- Consumes: `vpc_id`, `private_subnet_ids` (from vpc outputs via Terragrunt `dependency`), `cluster_version="1.31"`, `eks_admin_principal_arns`, `project`, `environment`
- Produces: `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `oidc_provider_arn`, `oidc_provider_url`, `cluster_security_group_id`
- Creates Fargate profiles: namespace `karpenter`; namespace `kube-system` (CoreDNS)
- Access Entry + `AmazonEKSClusterAdminPolicy` for each ARN in `eks_admin_principal_arns`
- Auth: `authentication_mode = "API"`

- [ ] **Step 1: Write terragrunt inputs contract test / validate config**

Assert `dependency.vpc.outputs.private_subnet_ids` wired; `skip = !enable_eks`.

- [ ] **Step 2: Implement module + live stacks**

- [ ] **Step 3: `terragrunt validate` in `live/dev/eks`**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add EKS module with Fargate profiles and Access Entries"
```

---

### Task 4: EKS add-ons module (flagged)

**Files:**
- Create: `modules/eks-addons/{main.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/eks-addons/terragrunt.hcl`

**Interfaces:**
- Consumes: cluster name/endpoint/CA, OIDC ARN/URL; bools `enable_vpc_cni`, `enable_coredns`, `enable_kube_proxy`, `enable_ebs_csi`, `enable_metrics_server`
- CoreDNS: configure `computeType = Fargate` when enabled
- Stack skip: `skip = !enable_eks_addons`
- Depends on: `eks`

- [ ] **Step 1: Implement module with per-addon `count` on flags**

- [ ] **Step 2: Wire terragrunt + validate**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add EKS add-ons module with feature flags"
```

---

### Task 5: Karpenter module

**Files:**
- Create: `modules/karpenter/{main.tf,iam.tf,variables.tf,outputs.tf,versions.tf}` (+ templates if needed)
- Create: `live/{dev,hml,prd}/karpenter/terragrunt.hcl`

**Interfaces:**
- Consumes: cluster outputs, subnet IDs, OIDC, `karpenter_version` default `1.1.1`
- Runs controller on Fargate (namespace `karpenter`, no node selector requiring EC2)
- Produces: `karpenter_role_arn`, `node_instance_profile_name`, interruption queue name
- Applies NodePool + EC2NodeClass (discovery tags matching VPC/EKS)
- Depends on: `eks`, `eks-addons`
- Skip: `!enable_karpenter`

- [ ] **Step 1: Implement IAM/IRSA + Helm + NodePool/EC2NodeClass**

- [ ] **Step 2: Validate terragrunt config**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add Karpenter module (controller on Fargate)"
```

---

### Task 6: Gateway API module (default off)

**Files:**
- Create: `modules/gateway-api/{main.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/gateway-api/terragrunt.hcl`

**Interfaces:**
- Consumes: cluster + OIDC + `vpc_id` + `region`
- Installs AWS Load Balancer Controller + Gateway API CRDs/controller as designed
- Skip: `!enable_gateway_api` (default false in env.hcl)
- Depends on: `karpenter` (nodes available for controller)

- [ ] **Step 1: Implement module + skip wiring**

- [ ] **Step 2: Prove skip — with flag false, `terragrunt plan` in stack reports skipped / no resources**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add Gateway API stack (disabled by default)"
```

---

### Task 7: ExternalDNS module (default off)

**Files:**
- Create: `modules/external-dns/{main.tf,iam.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/external-dns/terragrunt.hcl`

**Interfaces:**
- Consumes: `domain_name`, `route53_hosted_zone_id`, OIDC, cluster, `environment`
- Domain filter: `{environment}.{domain_name}` (e.g. `dev.brttech.dev`) — **not** apex
- Policy: `route53:ChangeResourceRecordSets` only on that hosted zone ARN
- Skip: `!enable_external_dns`
- Depends on: `eks` (and preferably `gateway-api` when both on)

- [ ] **Step 1: Write policy test / document assertion that apex is excluded**

Assert domain filter equals `"${environment}.${domain_name}"` and zone ID equals `Z09087232IC05YG46FH45` from env.

- [ ] **Step 2: Implement module + skip wiring**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add ExternalDNS stack scoped to env subdomain (disabled by default)"
```

---

### Task 8: ArgoCD module (default off)

**Files:**
- Create: `modules/argocd/{main.tf,variables.tf,outputs.tf,versions.tf}`
- Create: `live/{dev,hml,prd}/argocd/terragrunt.hcl`
- Optional: `helm/argocd-values.yaml`

**Interfaces:**
- Consumes: cluster auth, `argocd_version` pin (choose one chart version in implement step, e.g. `7.7.16` or document)
- Namespace `argocd`; runs on Karpenter nodes (no Fargate profile for argocd)
- Skip: `!enable_argocd`
- Depends on: `karpenter`

- [ ] **Step 1: Implement Helm release + terragrunt**

- [ ] **Step 2: Validate skip when false**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add ArgoCD stack (disabled by default)"
```

---

### Task 9: README + apply/destroy runbook + V2 multi-account note

**Files:**
- Create/Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-11-17-eks-blueprint-design.md` status → Approved

**Interfaces:**
- Documents: bootstrap state → edit `env.hcl` → `terragrunt run-all apply --terragrunt-working-dir live/dev`
- Documents destroy order (reverse deps)
- Documents V2 path `live/{env}/{account}/{stack}/`

- [ ] **Step 1: Write README with exact commands for lab account**

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: add apply runbook and multi-account V2 path"
```

---

### Task 10: Integration smoke (dev) — optional gated on AWS credentials

**Files:** none new (runbook verification)

- [ ] **Step 1: Bootstrap state in `280912093812`**

- [ ] **Step 2: `terragrunt run-all plan` in `live/dev` with defaults**

Expected: VPC, EKS, add-ons, Karpenter planned; gateway/external-dns/argocd skipped

- [ ] **Step 3: If user approves apply — apply VPC then EKS chain; verify Access Entry + CoreDNS on Fargate + Karpenter pod on Fargate**

- [ ] **Step 4: Commit any fixes discovered (no force-push)**

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Terragrunt + modules + env layout | 1–2 |
| Single env.hcl + flags | 1, 4–8 |
| 3 VPCs / CIDRs / NAT / tags | 2 |
| EKS + Access Entry SSO | 3 |
| Karpenter + CoreDNS Fargate | 3–5 |
| Gateway / ExternalDNS / ArgoCD default false | 6–8 |
| Domain/zone ExternalDNS scope | 7 |
| Remote state | 1 |
| Multi-account V2 documented | 9 |
| Operator UX copy/edit/apply | 9–10 |
