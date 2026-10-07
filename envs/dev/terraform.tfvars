environment        = "dev"
vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true # cost: one NAT is fine for dev

eks_endpoint_public_access       = true
eks_endpoint_public_access_cidrs = ["203.0.113.0/24"] # office/VPN range only (example)

node_groups = {
  general = {
    instance_types = ["t3.large"]
    capacity_type  = "SPOT"
    min_size       = 1
    desired_size   = 2
    max_size       = 3
  }
}

db_instance_class        = "db.t4g.medium"
db_instance_count        = 1
db_backup_retention_days = 1
db_deletion_protection   = false
