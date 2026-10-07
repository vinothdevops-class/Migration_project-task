# End-to-End Cloud Migration (Infra + Application + Data)
Target cloud: **AWS us-east-1** (EKS, Aurora MySQL 8.0, S3, Secrets Manager, KMS, DMS).
## What is here
This repository contains an end-to-end AWS cloud migration project covering infrastructure, application, database migration, security, CI/CD, and cost optimisation. The target platform is AWS us-east-1.
Migration Strategy — Migration assessment, dependency analysis, phased migration plan, cutover and rollback strategy.
AWS Infrastructure — VPC, private/public subnets, EKS, ALB, NAT, Aurora, VPC endpoints and Terraform infrastructure as code.
Application Containerisation — Node.js 22 application, Docker multi-stage build and Kubernetes deployment with health checks and autoscaling.
Payment Deployment — Secure Blue/Green deployments using Argo Rollouts with automated validation and rollback.
Database Migration — AWS DMS full-load + CDC migration from MySQL to Aurora MySQL 8.0 with controlled cutover and rollback.
Networking & Security — Network segmentation, default-deny controls, payment isolation, TLS/mTLS, Security Groups and Kubernetes NetworkPolicies.
Secrets Management — AWS Secrets Manager, KMS, IRSA, least-privilege IAM and credential rotation.
CI/CD — GitHub Actions pipeline for testing, Docker build, Trivy security scanning, ECR publishing, Dev/Staging/Prod promotion, approvals and rollback.
Cost Optimisation — Savings Plans, Aurora right-sizing, non-production scheduling, S3 lifecycle policies, Spot workloads and network cost optimisation.

## How to run / review

```bash
# App: lint + tests
cd app/order-service && npm ci && npm run lint && npm test

# K8s: render + validate
for e in dev staging prod; do kustomize build k8s/order-service/overlays/$e | kubeconform -strict -summary -kubernetes-version 1.33.0; done

# Terraform (needs AWS credentials; creates billable resources)
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply -var environment=dev
cd stacks/order-management
terraform init -backend-config=../../envs/dev/backend.hcl -reconfigure
terraform validate
terraform plan -var-file=../../envs/dev/terraform.tfvars -out=dev.plan

# DB migration (from an operator host in the VPC)
bash database/migration/dms/01-full-load-and-cdc.sh
python3 database/migration/validate/validate.py --source-secret ... --target-secret ... --source-ca ... --target-ca ...
```

## State management
S3 backend, one bucket per AWS account (KMS-encrypted, versioned, public access blocked, TLS-only),
S3-native locking (`use_lockfile = true`, Terraform >= 1.10), separate account + bucket + key per environment.
Applies run only from CI (plan on PR, apply on merge, approval for prod).

## Completed vs assumed vs not run

| Item | Status |
|---|---|
| Order service lint, 6 unit tests, `npm audit` | **Passed** locally |
| K8s manifests (27 objects, 3 envs) | **Valid** (`kubeconform -strict`, K8s 1.33) |
| Terraform | HCL syntax checked; `terraform validate/plan` **not run** (no Terraform binary/AWS account in the authoring sandbox) |
| Docker build + Trivy | **Not run** locally (registry access blocked); runs in CI |
| DMS migration, cutover timing, payment release | **Design + scripts only**; must be rehearsed in staging |
| Payment service code | Not included – the release and isolation design is documented; `order-service` is the containerised example |
| Account IDs, ARNs, hostnames, CIDRs | **Placeholders** |


Before production: pin GitHub Actions and base images by SHA/digest, configure GitHub Environments
(`dev`, `staging`, `prod` with 2 required reviewers) and variables (`AWS_BUILD_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN`, `CLUSTER_NAME`),
and set up ECR cross-account replication to the staging/prod account
