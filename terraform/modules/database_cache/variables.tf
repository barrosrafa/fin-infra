variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "subnet_ids" {
  description = "Lista de subnets de banco e cache (isoladas)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security Group ID para o cluster Redis"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN da chave KMS para criptografia em repouso"
  type        = string
}

variable "node_type" {
  description = "Tipo de instancia ElastiCache Redis"
  type        = string
  default     = "cache.t4g.medium"
}

variable "num_cache_clusters" {
  description = "Numero de nos no Replication Group (2+ habilita Multi-AZ com Failover automatico)"
  type        = number
  default     = 2
}

variable "auth_token" {
  description = "Token de autenticacao seguro para conexao Redis AUTH (minimo 16 caracteres)"
  type        = string
  sensitive   = true
}

variable "neon_database_url" {
  description = "URL de conexao do Neon Serverless PostgreSQL 18"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  description = "Tags padrao para os recursos"
  type        = map(string)
  default     = {}
}
