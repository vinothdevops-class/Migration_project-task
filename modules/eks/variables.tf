variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  type = string
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Keep false in prod; CI/CD and admins reach the API via VPN or in-VPC runners"
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "ebs_kms_key_arn" {
  type    = string
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "access_entries" {
  description = "IAM principal -> EKS access policy (+ optional namespace scope)"
  type = map(object({
    principal_arn = string
    policy_arn    = string
    namespaces    = optional(list(string), [])
  }))
  default = {}
}

variable "node_groups" {
  type = map(object({
    instance_types = list(string)
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = number
    desired_size   = number
    max_size       = number
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}
