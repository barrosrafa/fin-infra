variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR principal da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Lista de zonas de disponibilidade para espalhamento multi-AZ"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Lista de CIDRs para as subnets públicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Lista de CIDRs para as subnets privadas de computação (ECS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

variable "database_subnet_cidrs" {
  description = "Lista de CIDRs para as subnets isoladas de banco e cache (Redis)"
  type        = list(string)
  default     = ["10.0.50.0/24", "10.0.60.0/24", "10.0.70.0/24"]
}

variable "enable_nat_gateway" {
  description = "Habilitar NAT Gateways para acesso de saída das subnets privadas"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usar um único NAT Gateway para economia em staging (false em production)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags padrão para os recursos"
  type        = map(string)
  default     = {}
}
