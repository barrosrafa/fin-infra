# ----------------------------------------------------
# BUCKET 1: Raw Payloads & Scraped Artifacts (Camada Bronze)
# ----------------------------------------------------
resource "aws_s3_bucket" "raw_payloads" {
  bucket        = "fin-raw-payloads-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "production"

  tags = merge(
    var.tags,
    {
      Name        = "fin-raw-payloads-${var.environment}"
      Environment = var.environment
      Purpose     = "Bronze Layer Raw JSON/PDF Storage"
    }
  )
}

resource "aws_s3_bucket_versioning" "raw_payloads" {
  bucket = aws_s3_bucket.raw_payloads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_payloads" {
  bucket = aws_s3_bucket.raw_payloads.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_payloads" {
  bucket = aws_s3_bucket.raw_payloads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_payloads" {
  bucket = aws_s3_bucket.raw_payloads.id

  rule {
    id     = "archive-and-cleanup"
    status = "Enabled"

    # Transfere payloads brutos antigos para camadas de menor custo
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    # Remove versoes antigas nao-correntes apos 60 dias
    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }
}

# ----------------------------------------------------
# BUCKET 2: dbt Artifacts, Manifests & Analytics Reports
# ----------------------------------------------------
resource "aws_s3_bucket" "dbt_artifacts" {
  bucket        = "fin-dbt-artifacts-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "production"

  tags = merge(
    var.tags,
    {
      Name        = "fin-dbt-artifacts-${var.environment}"
      Environment = var.environment
      Purpose     = "dbt Docs and Compiled Manifests"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------
# BUCKET 3: Database Backups & Snapshots
# ----------------------------------------------------
resource "aws_s3_bucket" "backups" {
  bucket        = "fin-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "production"

  tags = merge(
    var.tags,
    {
      Name        = "fin-backups-${var.environment}"
      Environment = var.environment
      Purpose     = "Database Snapshots & WAL Archives"
    }
  )
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}
