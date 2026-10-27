output "redis_primary_endpoint" {
  description = "Endereco primario do endpoint do Redis para escritas e leituras"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Endereco do leitor do endpoint do Redis para distribuir leituras"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  description = "Porta do Redis"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_connection_url" {
  description = "URL completa formatada para conexao redis://"
  value       = "rediss://:${var.auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}/0"
  sensitive   = true
}
