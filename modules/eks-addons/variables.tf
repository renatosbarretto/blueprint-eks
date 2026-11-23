variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "enable_ebs_csi" {
  type    = bool
  default = true
}

variable "enable_metrics_server" {
  type    = bool
  default = true
}

variable "enable_node_monitoring_agent" {
  type    = bool
  default = true
}

variable "enable_cloudwatch_observability" {
  type    = bool
  default = false
}

variable "eks_addon_versions" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
