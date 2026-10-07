variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR, e.g. 10.10.0.0/16 (use non-overlapping ranges per env and vs on-prem for VPN)"
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "true = one NAT for cost (dev); false = one NAT per AZ for HA (staging/prod)"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name, used for subnet discovery tags"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "flow_log_retention_days" {
  type    = number
  default = 365
}

variable "logs_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key to encrypt flow logs"
}
