# Blueprint EKS — Kubernetes on AWS with Terraform

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Karpenter](https://img.shields.io/badge/Karpenter-FF6B35?style=for-the-badge&logo=amazon-eks&logoColor=white)

Modular Terraform blueprint for an Amazon EKS cluster with Karpenter autoscaling, private networking, KMS encryption, Gateway API (AWS Load Balancer Controller) and ArgoCD. Each environment (dev, staging, prod) has its own remote state.

> **Status:** the configuration passes `terraform validate` and offline tests that use mocked providers. Create, update and destroy a stack in a disposable account before you run it in production.

---

## What this repository deploys

| Area | Implementation |
|------|----------------|
| Network | VPC with public/private subnets per AZ, NAT gateway (single or per AZ), VPC flow logs, optional secondary CIDR (`10.147.0.0/16`) for VPC CNI custom networking |
| Control plane | EKS (default `1.34`), API authentication mode (Access Entries), KMS secrets encryption, control-plane logs, IRSA. Private endpoint by default; a public endpoint requires an explicit CIDR allowlist |
| Compute | **Karpenter 1.9** (controller and CoreDNS on Fargate; EC2 nodes on AL2023, Spot + On-Demand, IMDSv2), or a managed node group |
| Interruption handling | SQS queue + EventBridge rules (Spot interruption, rebalance, state change, AWS Health), with the queue policy scoped by `SourceArn` |
| Storage | gp3 root volumes encrypted with a dedicated KMS key; EBS CSI driver with KMS permissions; optional EFS CSI driver with its own IRSA role |
| Ingress | AWS Load Balancer Controller **v2.14.1** (chart 1.14.1) with `ALBGatewayAPI` enabled, Gateway API standard CRDs **v1.2.0** + LBC gateway CRDs |
| GitOps | ArgoCD (Helm) |
| Access | Optional IAM Identity Center access entry and RBAC binding; optional GitHub Actions OIDC role limited to one protected GitHub environment |

Options that are declared but not implemented (`enable_eks_auto_mode`, `enable_cluster_autoscaling`, `enable_vpn_gateway`) are rejected by variable validation instead of being silently ignored.

## Architecture

```
                       ┌──────────────── VPC 10.0.0.0/16 ────────────────┐
                       │  public subnets (NAT, ALB)                       │
 GitHub Actions ──OIDC─┤  private subnets ──────────────────────────────┐ │
 (protected env,       │   ┌──────────── EKS control plane ───────────┐ │ │
  self-hosted runner)  │   │ private endpoint · KMS · Access Entries   │ │ │
                       │   └──────────────────────────────────────────┘ │ │
                       │   Fargate: karpenter, coredns                  │ │
                       │   EC2 (Karpenter NodePool): workloads, add-ons │ │
                       │   optional 10.147.0.0/16 pod subnets (ENIConfig)│ │
                       └──────────────────────────────────────────────────┘
        EventBridge ──▶ SQS ──▶ Karpenter (interruption handling)
```

Apply order: VPC → EKS + Fargate profiles → bootstrap add-ons (VPC CNI, CoreDNS) → Karpenter + NodePool/EC2NodeClass → remaining add-ons → Gateway API → ArgoCD.

## Repository layout

```
.github/workflows/
  terraform.yml        # push/PR: static checks, fmt, validate, offline tests (no AWS credentials)
  deploy.yml           # manual: plan or apply one environment through OIDC
terraform/
  main.tf variables.tf outputs.tf providers.tf versions.tf
  modules/             # vpc, secondary-network, eks-cluster, eks-addons, karpenter,
                       # gateway-api, argocd, iam-identity-center, github-actions-oidc
  environments/<env>/  # terraform.tfvars.example + backend.tfbackend.example
  templates/           # Karpenter NodePool/EC2NodeClass, ENIConfigs
  tests/               # terraform test with mocked providers
helm/                  # values passed to ArgoCD, Karpenter and the LB controller
kubernetes/            # ArgoCD config and sample workload
scripts/               # init / deploy / destroy (per-environment state) + diagnostics
```

## Requirements

- Terraform `>= 1.11` (CI uses 1.15.1); providers are pinned in `terraform/.terraform.lock.hcl`
- AWS CLI v2, `kubectl`, `bash`
- An S3 bucket for state (versioning enabled; S3 native locking via `use_lockfile`)
- Network access to the private EKS endpoint (VPN, bastion or self-hosted runner) during apply, because Terraform installs Helm charts and Kubernetes manifests

## Usage

```bash
git clone https://github.com/renatosbarretto/blueprint-eks.git
cd blueprint-eks

# 1. Configure one environment (both files are git-ignored)
cp terraform/environments/dev/terraform.tfvars.example  terraform/environments/dev/terraform.tfvars
cp terraform/environments/dev/backend.tfbackend.example terraform/environments/dev/backend.tfbackend
#    set aws_account_id, region, CIDRs and the state bucket

# 2. Initialise, plan, review, apply
./scripts/init.sh dev
./scripts/deploy.sh dev          # shows the plan, asks you to type "dev" before applying

# 3. Connect
aws eks update-kubeconfig --region us-east-1 --name eks-blueprint-dev
kubectl get nodes,nodepools,ec2nodeclasses
```

Each environment uses its own `TF_DATA_DIR` (`terraform/.tfdata/<env>`) and state key (`eks-blueprint/<env>/terraform.tfstate`). The scripts refuse to run when the tfvars `environment` or the backend key does not match the selected environment. `provider "aws"` is pinned to `aws_account_id` through `allowed_account_ids`.

To destroy an environment, run `./scripts/destroy.sh dev`. The script creates a destroy plan and applies it only after you type `destroy-dev`.

### Remote state

Create a dedicated S3 bucket with versioning, default encryption and Block Public Access, then set `bucket` in `backend.tfbackend`. Keep `key = "eks-blueprint/<env>/terraform.tfstate"`; the scripts reject other keys. Locking uses S3 native lock files (`use_lockfile = true`), so no DynamoDB table is needed. Never commit `terraform.tfstate`, `tfplan` or `*.tfplan`, because plans contain a copy of the state.

### Draining one node

```bash
./scripts/cordon-and-rollout.sh <expected-kube-context> <node-name>
```

The script checks the context, refuses Fargate nodes, asks you to confirm the node name, respects PodDisruptionBudgets and uncordons the node if the drain fails. In normal operation, prefer Karpenter disruption (drift, consolidation, expiry).

### Recovery without state

`scripts/cleanup-aws-resources.sh` is retired: the old version deleted resources by name pattern and could release Elastic IPs that belonged to other projects. Instead, restore the previous state version from the versioned S3 bucket (or `terraform import` the remaining resources), then run `./scripts/destroy.sh <env>` and review the destroy plan before you confirm it.

### Upgrades

- Kubernetes: change `cluster_version` one minor version at a time, after you check the Karpenter compatibility matrix.
- Gateway API: upgrade the LB controller and the CRDs together in `modules/gateway-api` (LBC v2.14.x requires Gateway API standard CRDs v1.2.0+).
- Pin `karpenter_ami_alias` (for example `al2023@v20260101`) in production so that node AMIs change only when you decide.

## CI/CD

- **Validate** (`terraform.yml`) runs on every push and pull request without AWS credentials: repository hygiene (no state, plans, tfvars or obvious secrets), YAML/JSON parsing, tfvars example parsing, `terraform fmt`, `validate`, `terraform test` and `bash -n`.
- **Deploy** (`deploy.yml`) is manual (`workflow_dispatch`) and runs only from `main`. It uses a protected GitHub environment, OIDC (`vars.AWS_ROLE_ARN`) and a self-hosted runner that can reach the private endpoint. It runs a plan only unless you select `apply`.

To set up the deploy workflow:

1. Bootstrap the stack once from an administrator session with `enable_github_actions_oidc = true`, `github_environment = "<env>"` and `github_deploy_policy_arns` set to managed policies you have reviewed. The policies must cover this stack (VPC, EKS, IAM, KMS, SQS, EventBridge, CloudWatch Logs) and the state bucket. Set `github_create_oidc_provider = false` if the account already has the GitHub OIDC provider.
2. Create a GitHub environment with the same name. Restrict it to the `main` branch and add required reviewers.
3. Set the environment variables `AWS_ROLE_ARN` (output `github_actions_role_arn`) and `AWS_REGION`, and the secrets `TFVARS_HCL` and `BACKEND_HCL` (contents of the two environment files).
4. Register a self-hosted runner with the labels `self-hosted, linux, eks-deploy`, network access to the private EKS endpoint, and the AWS CLI, `kubectl` and `python3` installed.

## Security defaults

- No static AWS keys. The OIDC trust is limited to `repo:<owner>/<repo>:environment:<env>`, and the deploy role gets only the managed policies that you pass in `github_deploy_policy_arns`.
- Private EKS endpoint by default; `0.0.0.0/0` is rejected for the public endpoint.
- IMDSv2 required (hop limit 1), encrypted root volumes, KMS for Kubernetes secrets.
- The Karpenter controller policy follows the upstream v1 policy (tag-scoped to the cluster).
- ArgoCD server TLS stays enabled; metrics-server verifies kubelet TLS.

## Background

The design comes from my work running EKS in a regulated financial environment. There, Karpenter Spot strategies, rightsizing and scheduled scale-down of non-production environments cut Kubernetes compute cost by 30–65%. Some tools from that environment are not part of this repository: CAST AI, Control Tower/SCPs, the observability stack and Azure DevOps pipelines.

## Author

**Renato Barreto** — Cloud & FinOps Specialist | SRE | DevOps

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/renatobarretto/)
