variable "environment" {
  description = "Ambiente de implantação"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "Regiao AWS principal"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC de producao"
  type        = string
  default     = "10.0.0.0/16"
}

variable "redis_auth_token" {
  description = "Token de autenticacao seguro do Redis AUTH em producao"
  type        = string
  sensitive   = true
}

variable "neon_database_url" {
  description = "URL do Neon PostgreSQL 18 para producao"
  type        = string
  sensitive   = true
}

variable "certificate_arn" {
  description = "ARN do certificado SSL/TLS no ACM para producao (ex: *.seudominio.com.br)"
  type        = string
  default     = ""
}
