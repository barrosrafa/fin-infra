output "alb_dns_name" {
  description = "DNS publico do Application Load Balancer em Staging"
  value       = module.gateway.alb_dns_name
}

output "redis_endpoint" {
  description = "Endpoint do Redis em Staging"
  value       = module.database_cache.redis_primary_endpoint
}

output "s3_raw_payloads_bucket" {
  description = "Bucket S3 para payloads brutos de scraping"
  value       = module.storage_s3.raw_payloads_bucket_id
}
