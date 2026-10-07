# -----------------------------------------------------------------------------
# Order Management stack: ONE root module, reused for dev / staging / prod.
# Environment differences live only in envs/<env>/terraform.tfvars and the
# state location in envs/<env>/backend.hcl.
#
#   terraform -chdir=stacks/order-management init -backend-config=../../envs/prod/backend.hcl
#   terraform -chdir=stacks/order-management plan -var-file=../../envs/prod/terraform.tfvars
# -----------------------------------------------------------------------------

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${local.name}-eks"
}

module "networking" {
  source             = "../../modules/networking"
  project            = var.project
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  cluster_name       = local.cluster_name
}

module "eks" {
  source                       = "../../modules/eks"
  cluster_name                 = local.cluster_name
  kubernetes_version           = var.kubernetes_version
  private_subnet_ids           = module.networking.private_subnet_ids
  node_security_group_id       = module.networking.node_security_group_id
  endpoint_public_access       = var.eks_endpoint_public_access
  endpoint_public_access_cidrs = var.eks_endpoint_public_access_cidrs
  access_entries               = var.eks_access_entries
  node_groups                  = var.node_groups
}

module "aurora" {
  source                = "../../modules/aurora"
  name                  = local.name
  data_subnet_ids       = module.networking.data_subnet_ids
  db_security_group_id  = module.networking.db_security_group_id
  instance_class        = var.db_instance_class
  instance_count        = var.db_instance_count
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
}

# ---------------- Object storage (replaces 2 TB NFS) ----------------
resource "aws_s3_bucket" "files" {
  bucket = "${local.name}-order-files"
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    id     = "tiering"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 180
      storage_class = "GLACIER"
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Encryption in transit: deny any non-TLS request to the bucket.
resource "aws_s3_bucket_policy" "files_tls_only" {
  bucket = aws_s3_bucket.files.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.files.arn, "${aws_s3_bucket.files.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# ---------------- IRSA: least-privilege pod identity per service ----------------
# Each service account gets ONLY the actions it needs, on ONLY its resources.
locals {
  oidc_host = replace(module.eks.oidc_issuer, "https://", "")

  service_roles = {
    order-service = {
      namespace = "orders"
      statements = [
        { actions = ["secretsmanager:GetSecretValue"], resources = [module.aurora.master_secret_arn] },
        { actions = ["kms:Decrypt"], resources = [module.aurora.kms_key_arn] },
      ]
    }
    batch-reports = {
      namespace = "batch"
      statements = [
        { actions = ["s3:PutObject"], resources = ["${aws_s3_bucket.files.arn}/reports/*"] },
        { actions = ["secretsmanager:GetSecretValue"], resources = [module.aurora.master_secret_arn] },
      ]
    }
  }
}

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.service_roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.key}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "irsa_perms" {
  for_each = local.service_roles
  dynamic "statement" {
    for_each = each.value.statements
    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each           = local.service_roles
  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json
}

resource "aws_iam_role_policy" "irsa" {
  for_each = local.service_roles
  role     = aws_iam_role.irsa[each.key].id
  policy   = data.aws_iam_policy_document.irsa_perms[each.key].json
}

# Note: the internet-facing ALB is created by the AWS Load Balancer Controller from a
# Kubernetes Ingress (HTTPS listener with ACM cert, ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06),
# placed in the public subnets tagged kubernetes.io/role/elb and using module.networking.alb_security_group_id.
