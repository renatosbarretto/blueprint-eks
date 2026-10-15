# Operations

## Remote state

1. Create a dedicated S3 bucket with versioning, default encryption and Block Public Access.
2. Copy `terraform/environments/<env>/backend.tfbackend.example` to `backend.tfbackend` and set `bucket`.
   Keep `key = "eks-blueprint/<env>/terraform.tfstate"`; the scripts reject other keys.
3. Locking uses S3 native lock files (`use_lockfile = true`); no DynamoDB table is required.

`tfvars` and `tfbackend` files are git-ignored. Never commit `terraform.tfstate`, `tfplan` or `*.tfplan`: plans contain a copy of the state.

## Local workflow

```bash
./scripts/init.sh   <env>   # terraform init with the environment backend and TF_DATA_DIR
./scripts/deploy.sh <env>   # plan -> type the environment name -> apply the saved plan
./scripts/destroy.sh <env>  # destroy plan -> type destroy-<env> -> apply the saved plan
```

Saved plans go to `terraform/.plans/<env>` (mode 700) and are deleted when the script exits.

## GitHub Actions deploy

1. Bootstrap the stack once from an administrator session with `enable_github_actions_oidc = true`,
   `github_environment = "<env>"`, and `github_deploy_policy_arns` set to managed policies you have reviewed.
   The policies must cover this stack (VPC, EKS, IAM roles/instance profiles/OIDC, KMS, SQS, EventBridge,
   CloudWatch Logs) and the state bucket. Set `github_create_oidc_provider = false` if the account already has the GitHub provider.
   Terraform also creates an EKS Access Entry with `AmazonEKSClusterAdminPolicy` for the role.
2. In GitHub, create an environment with the same name. Restrict deployments to the `main` branch and add required reviewers.
3. Set the environment variables `AWS_ROLE_ARN` (output `github_actions_role_arn`) and `AWS_REGION`.
   Set the environment secrets `TFVARS_HCL` and `BACKEND_HCL` to the contents of the two environment files.
4. Register a self-hosted runner with the labels `self-hosted, linux, eks-deploy`. The runner must reach the private EKS endpoint
   and have the AWS CLI, `kubectl` and `python3` installed.
5. Run **Deploy** manually. It runs a plan only unless you select `apply`.

## Draining one node

```bash
./scripts/cordon-and-rollout.sh <expected-kube-context> <node-name>
```

The script checks the context, refuses Fargate nodes, asks you to confirm the node name, respects PodDisruptionBudgets,
and uncordons the node if the drain fails. In normal operation, prefer Karpenter disruption (drift, consolidation, expiry).

## Recovery without state

`scripts/cleanup-aws-resources.sh` is retired. The old version deleted resources by name pattern and could release
Elastic IPs that belonged to other projects. To recover:

1. Restore the previous state object version from the versioned S3 bucket, or
2. `terraform import` the remaining resources into a fresh state for that environment,
3. then run `./scripts/destroy.sh <env>` and review the destroy plan before you confirm it.

## Upgrades

- Kubernetes: change `cluster_version` one minor version at a time. Check the Karpenter compatibility matrix first.
- Karpenter: `karpenter_version` updates the chart; the NodePool/EC2NodeClass manifests are re-applied when they change.
- Gateway API: the LB controller version and the CRDs are upgraded together in `modules/gateway-api`
  (LBC v2.14.x requires Gateway API standard CRDs v1.2.0+).
- Pin `karpenter_ami_alias` (for example `al2023@v20260101`) in production so that node AMIs change only when you decide.
