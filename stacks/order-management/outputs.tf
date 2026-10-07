output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "aurora_writer_endpoint" {
  value = module.aurora.writer_endpoint
}

output "aurora_secret_arn" {
  value = module.aurora.master_secret_arn
}

output "files_bucket" {
  value = aws_s3_bucket.files.bucket
}

output "irsa_role_arns" {
  value = { for k, r in aws_iam_role.irsa : k => r.arn }
}
