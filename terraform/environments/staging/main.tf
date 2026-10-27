terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Configuração de Backend Remoto S3 + DynamoDB (Preencher para deploy real)
  # backend "s3" {
  #   bucket         = "fin-terraform-state-staging"
  #   key            = "staging/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "fin-terraform-locks-staging"
  #   encrypt        = true
  # }
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

# 1. VPC & Networking
module "vpc" {
  source = "../../modules/vpc"

  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs   = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs  = ["10.10.10.0/24", "10.10.20.0/24"]
  database_subnet_cidrs = ["10.10.50.0/24", "10.10.60.0/24"]
  enable_nat_gateway    = true
  single_nat_gateway    = true # Economia para staging
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

# 5. Database & Cache (Redis ElastiCache + Neon SSM)
module "database_cache" {
  source = "../../modules/database_cache"

  environment        = var.environment
  subnet_ids         = module.vpc.database_subnet_ids
  security_group_id  = module.security.redis_security_group_id
  kms_key_arn        = module.security.kms_key_arn
  node_type          = "cache.t4g.small"
  num_cache_clusters = 1 # 1 no para staging
  auth_token         = var.redis_auth_token
  neon_database_url  = var.neon_database_url
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

# 7. Compute ECS Fargate (API & Worker)
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

  api_cpu             = 256
  api_memory          = 512
  api_min_capacity    = 1
  api_max_capacity    = 4
  worker_cpu          = 256
  worker_memory       = 512
  worker_min_capacity = 1
  worker_max_capacity = 3

  redis_url_secret_arn = module.database_cache.redis_connection_url
}
