output "writer_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "master_secret_arn" {
  description = "Secrets Manager ARN holding the rotated master credentials"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  value = aws_kms_key.db.arn
}
