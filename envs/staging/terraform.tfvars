environment        = "staging"
vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = true

node_groups = {
  general = {
    instance_types = ["m6i.large"]
    min_size       = 2
    desired_size   = 3
    max_size       = 6
  }
  payment = {
    instance_types = ["m6i.large"]
    min_size       = 2
    desired_size   = 2
    max_size       = 4
    labels         = { workload = "payment", pci = "true" }
    taints         = [{ key = "pci", value = "true", effect = "NO_SCHEDULE" }]
  }
}

db_instance_class        = "db.r6g.large"
db_instance_count        = 2
db_backup_retention_days = 7
db_deletion_protection   = true
