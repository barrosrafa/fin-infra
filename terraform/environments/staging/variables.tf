variable "environment" {
  description = "Ambiente de implantação"
  type        = string
  default     = "staging"
}

variable "aws_region" {
  description = "Regiao AWS principal"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC de staging"
  type        = string
  default     = "10.10.0.0/16"
}

variable "redis_auth_token" {
  description = "Token de autenticacao do Redis AUTH"
  type        = string
  sensitive   = true
  default     = "StagingSuperSecureAuthToken12345!"
}

variable "neon_database_url" {
  description = "URL do Neon PostgreSQL 18 para staging"
  type        = string
  sensitive   = true
  default     = ""
}

variable "certificate_arn" {
  description = "ARN do certificado SSL/TLS no ACM para staging"
  type        = string
  default     = ""
}
