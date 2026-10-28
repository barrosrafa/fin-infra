terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Configuração de Backend Remoto S3 + DynamoDB para Produção
  backend "s3" {
    bucket         = "fin-terraform-state-production"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fin-terraform-locks-production"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "fin"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# 1. VPC & Networking (Alta Disponibilidade com 3 Zonas)
module "vpc" {
  source = "../../modules/vpc"

  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs  = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  database_subnet_cidrs = ["10.0.50.0/24", "10.0.60.0/24", "10.0.70.0/24"]
  enable_nat_gateway    = true
  single_nat_gateway    = false # Multi-AZ NAT Gateways para resiliencia em producao
}

# 2. Segurança, IAM & KMS
module "security" {
  source = "../../modules/security"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

# 3. Segredos & Credenciais
module "secrets" {
  source = "../../modules/secrets"

  environment = var.environment
  kms_key_arn = module.security.kms_key_arn
}

# 4. Storage S3
module "storage_s3" {
  source = "../../modules/storage_s3"

  environment = var.environment
  kms_key_arn = module.security.kms_key_arn
}

# 5. Database & Cache (Redis ElastiCache Multi-AZ + Neon SSM)
module "database_cache" {
  source = "../../modules/database_cache"

  environment        = var.environment
  subnet_ids         = module.vpc.database_subnet_ids
  security_group_id  = module.security.redis_security_group_id
  kms_key_arn        = module.security.kms_key_arn
  node_type          = "cache.t4g.medium"
  num_cache_clusters = 2 # Multi-AZ com failover automatico
  auth_token         = var.redis_auth_token
  neon_database_url  = var.neon_database_url
}

resource "aws_secretsmanager_secret" "redis_url" {
  name                    = "fin/${var.environment}/redis-url"
  description             = "Redis connection URL for ECS tasks"
  kms_key_id              = module.security.kms_key_arn
  recovery_window_in_days = 0

  tags = {
    Name        = "fin-${var.environment}-redis-url"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id     = aws_secretsmanager_secret.redis_url.id
  secret_string = module.database_cache.redis_connection_url
}

# 6. Ingress Gateway & ALB
module "gateway" {
  source = "../../modules/gateway"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  certificate_arn       = var.certificate_arn
}

# 7. Compute ECS Fargate (API & Worker com Autoscaling)
module "compute_ecs" {
  source = "../../modules/compute_ecs"

  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  api_security_group_id    = module.security.api_security_group_id
  worker_security_group_id = module.security.worker_security_group_id
  ecs_execution_role_arn   = module.security.ecs_execution_role_arn
  ecs_task_role_arn        = module.security.ecs_task_role_arn
  target_group_arn         = module.gateway.target_group_arn

  api_cpu             = 1024
  api_memory          = 2048
  api_min_capacity    = 2
  api_max_capacity    = 10
  worker_cpu          = 1024
  worker_memory       = 2048
  worker_min_capacity = 2
  worker_max_capacity = 8

  redis_url_secret_arn = aws_secretsmanager_secret.redis_url.arn
}
