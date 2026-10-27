variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde as tasks Fargate serao executadas"
  type        = list(string)
}

variable "api_security_group_id" {
  description = "Security Group ID para os containers da API"
  type        = string
}

variable "worker_security_group_id" {
  description = "Security Group ID para os containers dos Workers"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN da ECS Task Execution Role"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN da ECS Task Runtime Role"
  type        = string
}

variable "target_group_arn" {
  description = "ARN do Target Group do ALB para a API HTTP"
  type        = string
}

variable "api_image" {
  description = "URI da imagem Docker para a API (ex: no ECR)"
  type        = string
  default     = "public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest"
}

variable "worker_image" {
  description = "URI da imagem Docker para o Worker ARQ"
  type        = string
  default     = "public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest"
}

variable "ingestion_image" {
  description = "URI da imagem Docker para pipelines de ingestao"
  type        = string
  default     = "public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest"
}

variable "api_cpu" {
  description = "CPU alocada para a Task API (em unidades: 256, 512, 1024, 2048)"
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "Memoria alocada para a Task API (em MB: 1024, 2048, 4096)"
  type        = number
  default     = 1024
}

variable "api_min_capacity" {
  description = "Capacidade minima de tasks da API"
  type        = number
  default     = 2
}

variable "api_max_capacity" {
  description = "Capacidade maxima de tasks da API (Autoscaling)"
  type        = number
  default     = 10
}

variable "worker_cpu" {
  description = "CPU alocada para a Task Worker"
  type        = number
  default     = 512
}

variable "worker_memory" {
  description = "Memoria alocada para a Task Worker"
  type        = number
  default     = 1024
}

variable "worker_min_capacity" {
  description = "Capacidade minima de workers"
  type        = number
  default     = 2
}

variable "worker_max_capacity" {
  description = "Capacidade maxima de workers (Autoscaling)"
  type        = number
  default     = 8
}

variable "redis_url_secret_arn" {
  description = "ARN do segredo/parametro com a URL de conexao do Redis"
  type        = string
  default     = ""
}

variable "database_url_secret_arn" {
  description = "ARN do segredo com a URL do PostgreSQL Neon"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags padrao"
  type        = map(string)
  default     = {}
}
