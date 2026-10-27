output "alb_dns_name" {
  description = "DNS publico do Application Load Balancer em Producao"
  value       = module.gateway.alb_dns_name
}

output "redis_primary_endpoint" {
  description = "Endpoint primario do Redis em Producao"
  value       = module.database_cache.redis_primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Endpoint de leitura do Redis em Producao"
  value       = module.database_cache.redis_reader_endpoint
}

output "s3_raw_payloads_bucket" {
  description = "Bucket S3 para payloads brutos de scraping"
  value       = module.storage_s3.raw_payloads_bucket_id
}

output "nat_gateway_ips" {
  description = "IPs publicos de saida para whitelist nos orgaos oficiais"
  value       = module.vpc.nat_gateway_ips
}
