environment        = "prod"
vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false # one NAT per AZ for HA

eks_endpoint_public_access = false # API reachable only from VPC / VPN

eks_access_entries = {
  platform-admins = {
    principal_arn = "arn:aws:iam::111111111111:role/PlatformAdmin"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
  orders-devs-readonly = {
    principal_arn = "arn:aws:iam::111111111111:role/OrdersDeveloper"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    namespaces    = ["orders"]
  }
  cicd-deployer = {
    principal_arn = "arn:aws:iam::111111111111:role/GitHubActionsDeployer"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    namespaces    = ["orders", "web", "batch"]
  }
}

node_groups = {
  general = {
    instance_types = ["m6i.xlarge", "m6a.xlarge"]
    min_size       = 3
    desired_size   = 4
    max_size       = 12 # headroom for sales events
  }
  payment = {
    instance_types = ["m6i.large"]
    min_size       = 2
    desired_size   = 3
    max_size       = 6
    labels         = { workload = "payment", pci = "true" }
    taints         = [{ key = "pci", value = "true", effect = "NO_SCHEDULE" }]
  }
  batch-spot = {
    instance_types = ["m6i.large", "m5.large", "m6a.large"]
    capacity_type  = "SPOT"
    min_size       = 0
    desired_size   = 0
    max_size       = 5
    labels         = { workload = "batch" }
    taints         = [{ key = "batch", value = "true", effect = "NO_SCHEDULE" }]
  }
}

db_instance_class        = "db.r6g.xlarge"
db_instance_count        = 3 # writer + 2 readers across AZs
db_backup_retention_days = 35
db_deletion_protection   = true
