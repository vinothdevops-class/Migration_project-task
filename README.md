# FinNova Order Management – Terraform (Task 2)

```
bootstrap/                 # once per account: encrypted, versioned S3 state bucket
modules/
  networking/              # VPC, public/private/data subnets, IGW, NAT, route tables, SGs, VPC endpoints, flow logs
  eks/                     # private EKS cluster, KMS secrets encryption, managed node groups (autoscaling), IRSA OIDC, access entries
  aurora/                  # Aurora MySQL 8.0, private, KMS, TLS-only, Secrets Manager-managed password
stacks/order-management/   # ONE root module composing the modules + S3 file bucket + IRSA roles
envs/{dev,staging,prod}/   # backend.hcl (state location) + terraform.tfvars (sizing) – the only per-env files
```

## Usage
```bash
# one-time per account
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply -var environment=prod

# deploy an environment
cd stacks/order-management
terraform init  -backend-config=../../envs/prod/backend.hcl -reconfigure
terraform plan  -var-file=../../envs/prod/terraform.tfvars -out=prod.plan
terraform apply prod.plan
```

## State management
- Backend: S3, one bucket per AWS account (dev/staging/prod are separate accounts), KMS-encrypted, versioned, public access blocked, TLS-only policy.
- Locking: S3-native lock file (`use_lockfile = true`, Terraform >= 1.10) – no DynamoDB table needed.
- Isolation: separate account + bucket + state key per environment; a prod apply can never touch dev state. Only the CI deploy role for that account can write its bucket.

Requires Terraform >= 1.10, AWS provider ~> 6.0. Account IDs / CIDRs in tfvars are examples.
