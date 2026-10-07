# -----------------------------------------------------------------------------
# Aurora MySQL 8.0 module: private data subnets only, never publicly accessible,
# KMS encryption at rest, TLS enforced in transit, master password generated and
# rotated by Secrets Manager (no password in code or state), IAM DB auth enabled.
# -----------------------------------------------------------------------------

resource "aws_kms_key" "db" {
  description             = "${var.name} Aurora storage + secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "db" {
  name          = "alias/${var.name}-aurora"
  target_key_id = aws_kms_key.db.key_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora"
  subnet_ids = var.data_subnet_ids # isolated subnets with no internet route
}

# Encryption in transit: server rejects any non-TLS connection.
resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.name}-aurora-mysql8"
  family = "aurora-mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }

  parameter {
    name  = "tls_version"
    value = "TLSv1.2,TLSv1.3"
    apply_method = "pending-reboot"
  }

  # binlog needed for DMS CDC from on-prem and for reverse replication (rollback)
  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "pending-reboot"
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name}-aurora"
  engine             = "aurora-mysql"
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username

  # Password is generated and stored in Secrets Manager by RDS, rotated automatically.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.db.key_id

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.db_security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.db.arn

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "02:00-03:00"
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = !var.deletion_protection
  final_snapshot_identifier    = var.deletion_protection ? "${var.name}-aurora-final" : null
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]
}

resource "aws_rds_cluster_instance" "this" {
  count                        = var.instance_count # 1 writer + (n-1) readers spread across AZs
  identifier                   = "${var.name}-aurora-${count.index}"
  cluster_identifier           = aws_rds_cluster.this.id
  engine                       = aws_rds_cluster.this.engine
  engine_version               = aws_rds_cluster.this.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.this.name
  publicly_accessible          = false
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.db.arn
  auto_minor_version_upgrade   = true
}
