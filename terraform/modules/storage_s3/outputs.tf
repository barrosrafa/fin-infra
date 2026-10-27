output "raw_payloads_bucket_id" {
  description = "Nome do bucket S3 de payloads brutos"
  value       = aws_s3_bucket.raw_payloads.id
}

output "raw_payloads_bucket_arn" {
  description = "ARN do bucket S3 de payloads brutos"
  value       = aws_s3_bucket.raw_payloads.arn
}

output "dbt_artifacts_bucket_id" {
  description = "Nome do bucket S3 de artefatos dbt"
  value       = aws_s3_bucket.dbt_artifacts.id
}

output "dbt_artifacts_bucket_arn" {
  description = "ARN do bucket S3 de artefatos dbt"
  value       = aws_s3_bucket.dbt_artifacts.arn
}

output "backups_bucket_id" {
  description = "Nome do bucket S3 de backups"
  value       = aws_s3_bucket.backups.id
}

output "backups_bucket_arn" {
  description = "ARN do bucket S3 de backups"
  value       = aws_s3_bucket.backups.arn
}
