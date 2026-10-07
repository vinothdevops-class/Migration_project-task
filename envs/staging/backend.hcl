# State isolation: one state file per environment, in a per-account state bucket.
bucket       = "finnova-tfstate-staging"
key          = "order-management/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true # S3-native state locking (Terraform >= 1.10), replaces DynamoDB lock table
