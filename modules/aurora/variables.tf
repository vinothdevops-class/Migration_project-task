variable "name" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "8.0.mysql_aurora.3.08.0"
}

variable "database_name" {
  type    = string
  default = "orders"
}

variable "master_username" {
  type    = string
  default = "admin_user"
}

variable "instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "instance_count" {
  type    = number
  default = 2
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}
