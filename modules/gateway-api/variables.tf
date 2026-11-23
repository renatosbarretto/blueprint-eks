variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "region" { type = string }

variable "lbc_chart_version" {
  type = string
}

variable "lbc_app_version" {
  description = "App version do LBC (CRDs gateway em crds/lbc-v<versão>-gateway-crds.yaml). Alinhar ao chart."
  type        = string
}

variable "gateway_api_version" {
  description = "Release do Gateway API (CRDs em crds/gateway-api-<versão>-standard.yaml)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
