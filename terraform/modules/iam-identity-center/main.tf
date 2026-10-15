# -----------------------------------------------------------------------------
# EKS Access Entry for IAM Identity Center (SSO) principal
# principal_arn = IAM role ARN created by IAM Identity Center when permission set
# is assigned (e.g. arn:aws:iam::ACCOUNT:role/aws-reserved/sso.amazonaws.com/REGION/AWSReservedSSO_admins-prod_xxx)
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "sso" {
  cluster_name      = var.cluster_name
  principal_arn     = var.principal_arn
  type              = "STANDARD"
  kubernetes_groups = ["eks-sso-admins"]
}

# -----------------------------------------------------------------------------
# Associate EKS admin access policy so the principal can access cluster API
# -----------------------------------------------------------------------------
resource "aws_eks_access_policy_association" "sso_admin" {
  cluster_name  = var.cluster_name
  principal_arn = var.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  depends_on    = [aws_eks_access_entry.sso]
  access_scope {
    type = "cluster"
  }
}

# -----------------------------------------------------------------------------
# Kubernetes RBAC: bind cluster-admin to the IAM principal
# When authenticating via IAM (SSO), the Kubernetes username is the role ARN
# -----------------------------------------------------------------------------
resource "kubernetes_cluster_role_binding_v1" "sso_cluster_admin" {
  metadata {
    name = var.rbac_cluster_role_binding_name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "eks-sso-admins"
  }
}
