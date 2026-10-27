# Subnet Group do ElastiCache Redis
resource "aws_elasticache_subnet_group" "redis" {
  name        = "fin-redis-subnet-group-${var.environment}"
  description = "Subnets isoladas para o cluster Redis ElastiCache"
  subnet_ids  = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name        = "fin-redis-subnet-group-${var.environment}"
      Environment = var.environment
    }
  )
}

# Parameter Group Customizado para Redis 7
resource "aws_elasticache_parameter_group" "redis7" {
  name        = "fin-redis7-params-${var.environment}"
  family      = "redis7"
  description = "Parametros otimizados para cache de alta performance e filas ARQ no Redis 7"

  # Maxmemory policy: volatile-lru para que keys sem TTL (como filas ARQ) nunca sejam descartadas
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = var.tags
}

# Replication Group do Redis 7 (Multi-AZ com Failover Automatico)
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "fin-redis-${var.environment}"
  description          = "Cluster Redis 7 para Cache de Cotacoes, Indicadores e Filas ARQ"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.security_group_id]

  # Alta Disponibilidade e Resiliencia
  automatic_failover_enabled = var.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = var.num_cache_clusters > 1 ? true : false

  # Criptografia Estrita (Em Transito e Em Repouso)
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  auth_token                 = var.auth_token

  # Backup & Snapshotting
  snapshot_retention_limit = var.environment == "production" ? 7 : 1
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"
  auto_minor_version_upgrade = true

  tags = merge(
    var.tags,
    {
      Name        = "fin-redis-${var.environment}"
      Environment = var.environment
    }
  )
}

# Armazenamento seguro da configuracao de conexao do Neon Serverless Postgres no SSM
resource "aws_ssm_parameter" "neon_database_url" {
  count       = var.neon_database_url != "" ? 1 : 0
  name        = "/fin/${var.environment}/database/url"
  description = "URL segura de conexao do Neon PostgreSQL 18 / TimescaleDB"
  type        = "SecureString"
  key_id      = var.kms_key_arn
  value       = var.neon_database_url

  tags = var.tags
}
