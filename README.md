# 🏗️ Blueprint EKS — Production-Grade Kubernetes on AWS

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Karpenter](https://img.shields.io/badge/Karpenter-FF6B35?style=for-the-badge&logo=amazon-eks&logoColor=white)
![CAST AI](https://img.shields.io/badge/CAST_AI-00C7B7?style=for-the-badge&logoColor=white)

> A production-ready EKS blueprint designed for enterprise environments, focused on **cost optimization**, **security**, **observability**, and **operational governance**. Originally built and battle-tested in a regulated financial institution environment.

---

## 📋 Overview

This blueprint defines a standardized, opinionated architecture for running Amazon EKS clusters at scale. It covers everything from cluster provisioning and networking to autoscaling, security hardening, observability, and CI/CD integration — with a strong FinOps-first mindset.

**Key results achieved with this blueprint:**
- 🟢 **30–65% reduction** in Kubernetes compute costs via intelligent autoscaling and Spot Instance strategy
- 🟢 **Automated node lifecycle management** with Karpenter and CAST AI
- 🟢 **Zero-downtime cluster upgrades** with managed addon versioning via Terraform
- 🟢 **Multi-account governance** with AWS Control Tower, SCPs, and guardrails

---

## 🏛️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   AWS Organization                       │
│   ┌─────────────┐  ┌──────────────┐  ┌───────────────┐ │
│   │  Management  │  │   Security   │  │  Workload     │ │
│   │   Account    │  │   Account    │  │  Accounts     │ │
│   └─────────────┘  └──────────────┘  └───────────────┘ │
│         AWS Control Tower + SCPs + Guardrails            │
└─────────────────────────────────────────────────────────┘
                          │
              ┌───────────▼───────────┐
              │      VPC Design       │
              │  Public + Private     │
              │  Subnets + NAT GW     │
              │  Transit Gateway      │
              └───────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │    EKS Cluster        │
              │  ┌─────────────────┐  │
              │  │  Managed Nodes  │  │
              │  │  + Spot (via    │  │
              │  │  Karpenter &    │  │
              │  │  CAST AI)       │  │
              │  └─────────────────┘  │
              │                       │
              │  NGINX Ingress + ALB  │
              │  RBAC + IRSA          │
              │  HPA + Cluster AS     │
              └───────────┬───────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   Observability      CI/CD Pipeline    Security
   (Prometheus,       (Azure DevOps     (GuardDuty,
    Grafana,           + GitFlow)        WAF, KMS,
    Loki, Dynatrace)                     SSM, IAM)
```

---

## ⚙️ Components

### 🖥️ Cluster Provisioning
| Component | Tool/Service |
|-----------|-------------|
| Infrastructure as Code | Terraform |
| Cluster Bootstrap | eksctl + Terraform EKS Module |
| Addon Management | Terraform (versioned, lifecycle-managed) |
| Multi-account Setup | AWS Control Tower + AFT |

### 🔄 Autoscaling & Cost Optimization (FinOps)
| Component | Tool/Service |
|-----------|-------------|
| Node Autoscaler | Karpenter |
| Spot Instance Strategy | Karpenter NodePools + Interruption Handling |
| Intelligent Rightsizing | CAST AI |
| Scheduled Scale-down (dev/hml) | CAST AI Policies |
| Auto Deployment Resize | CAST AI |

### 🌐 Networking & Ingress
| Component | Tool/Service |
|-----------|-------------|
| Ingress Controller | NGINX Ingress Controller |
| Load Balancer | AWS ALB (Application Load Balancer) |
| Network Segmentation | VPC + Subnets + NACLs |
| Cross-account Connectivity | Transit Gateway + VPC Peering |
| DNS | Route53 |
| TLS | AWS Certificate Manager |

### 🔐 Security & Governance
| Component | Tool/Service |
|-----------|-------------|
| Pod Permissions | IRSA (IAM Roles for Service Accounts) |
| Secrets Management | AWS SSM Parameter Store + KMS |
| Threat Detection | Amazon GuardDuty |
| WAF | AWS WAF |
| Org Governance | SCPs (Service Control Policies) |
| Compliance | AWS Config Rules + Guardrails |
| Audit | AWS CloudTrail |

### 📊 Observability
| Component | Tool/Service |
|-----------|-------------|
| Metrics | Prometheus + CloudWatch |
| Dashboards | Grafana |
| Log Aggregation | Loki / CloudWatch Logs |
| APM | Dynatrace / New Relic |
| Health & Compliance | AWS Trusted Advisor |

### 🚀 CI/CD
| Component | Tool/Service |
|-----------|-------------|
| Pipeline | Azure DevOps |
| Branching Strategy | GitFlow |
| Infra Deployments | Terraform via pipeline stages |
| App Deployments | .NET APIs via automated stages |

---

## 📁 Repository Structure

```
blueprint-eks/
├── modules/
│   ├── eks-cluster/          # EKS cluster definition
│   ├── karpenter/            # Karpenter node provisioner setup
│   ├── cast-ai/              # CAST AI integration & policies
│   ├── networking/           # VPC, subnets, TGW, peering
│   ├── security/             # IAM, IRSA, GuardDuty, WAF
│   ├── ingress/              # NGINX Ingress + ALB config
│   └── observability/        # Monitoring stack
├── environments/
│   ├── dev/
│   ├── hml/
│   └── prd/
├── addons/                   # EKS managed addons config
├── policies/                 # Karpenter NodePools & CAST AI policies
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl
- helm >= 3.x
- eksctl (optional, for bootstrap)

### Deploy

```bash
# Clone the repository
git clone https://github.com/renatosbarretto/blueprint-eks.git
cd blueprint-eks

# Initialize Terraform
terraform init

# Plan for your target environment
terraform plan -var-file="environments/prd/terraform.tfvars"

# Apply
terraform apply -var-file="environments/prd/terraform.tfvars"
```

---

## 💡 FinOps Highlights

This blueprint was designed with **cost efficiency as a first-class concern**:

- **Karpenter** provisions the cheapest available Spot Instance type that satisfies workload requirements, with automatic fallback to On-Demand.
- **CAST AI** continuously analyzes running workloads and rightsizes CPU/Memory requests, eliminating over-provisioning.
- **Scheduled policies** shut down dev and staging nodes outside business hours — reducing non-production compute costs by up to 65%.
- **Spot interruption handling** ensures graceful node draining before AWS reclaims capacity.
- All cost metrics are tracked and exposed to FinOps dashboards.

---

## 🔒 Security Highlights

- **Least-privilege IAM** enforced via IRSA — no node-level credentials.
- **SCPs at Organization level** prevent security policy bypass across all accounts.
- **Network isolation** with private node groups — no public access to worker nodes.
- **Encrypted secrets** via KMS — no plaintext credentials in code or environment variables.
- **GuardDuty** for continuous threat detection across the cluster and AWS accounts.
- **AWS Config rules** for automated compliance checks and drift detection.

---

## 📈 Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Compute Cost (Kubernetes) | Baseline | Optimized | **-30% to -65%** |
| Node Provisioning Time | ~5 min | ~60 sec | **~80% faster** |
| Compliance Score (AWS Config) | Low | High | **Significantly improved** |
| Manual Infra Operations | High | Near-zero | **Automated** |
| Dev/HML environment cost | 24/7 running | Business hours only | **~65% reduction** |

---

## 🧑‍💻 Author

**Renato Barreto**
Cloud & FinOps Specialist | SRE | DevOps

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/renatobarretto/)

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
