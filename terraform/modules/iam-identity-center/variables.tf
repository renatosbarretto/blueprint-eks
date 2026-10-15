variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN (for dependency)."
  type        = string
}

# -----------------------------------------------------------------------------
# IAM Identity Center: use the IAM role ARN that SSO creates when the permission
# set is assigned (arn:aws:iam::ACCOUNT:role/aws-reserved/sso.amazonaws.com/REGION/AWSReservedSSO_<Name>_<Id>)
# -----------------------------------------------------------------------------
variable "principal_arn" {
  description = "IAM role ARN for the IAM Identity Center permission set in this account (e.g. AWSReservedSSO_admins-prod_xxx). Obtain via: aws iam list-roles --query 'Roles[?starts_with(RoleName, `AWSReservedSSO`)].Arn'."
  type        = string
}

variable "permission_set_arn" {
  description = "Permission set ARN (for reference/documentation only; EKS uses principal_arn)."
  type        = string
  default     = null
}

variable "permission_sets" {
  description = "Map of permission set names to config (unused in this module; for reference)."
  type        = map(any)
  default     = {}
}

variable "rbac_cluster_role_binding_name" {
  description = "Name of the ClusterRoleBinding that grants cluster-admin to the SSO principal."
  type        = string
  default     = "sso-cluster-admin"
}

variable "tags" {
  description = "Tags for AWS resources."
  type        = map(string)
  default     = {}
}
