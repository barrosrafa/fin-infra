# ECS Cluster com Container Insights ativado
resource "aws_ecs_cluster" "main" {
  name = "fin-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-cluster-${var.environment}"
      Environment = var.environment
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.environment == "production" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 100
    base              = 1
  }
}

# ----------------------------------------------------
# CLOUDWATCH LOG GROUPS
# ----------------------------------------------------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/fin-api-${var.environment}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/fin-worker-${var.environment}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ingestion" {
  name              = "/ecs/fin-ingestion-${var.environment}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = var.tags
}

# ----------------------------------------------------
# TASK DEFINITIONS
# ----------------------------------------------------

# Task Definition da API HTTP (FastAPI)
resource "aws_ecs_task_definition" "api" {
  family                   = "fin-api-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "fin-api"
      image     = var.api_image
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      command = ["python", "-m", "app.cli", "serve", "--host", "0.0.0.0", "--port", "8000"]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "LOG_LEVEL", value = var.environment == "production" ? "INFO" : "DEBUG" },
        { name = "PROMETHEUS_METRICS_ENABLED", value = "true" }
      ]

      secrets = concat(
        var.database_url_secret_arn != "" ? [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }] : [],
        var.redis_url_secret_arn != "" ? [{ name = "REDIS_URL", valueFrom = var.redis_url_secret_arn }] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = var.tags
}

# Task Definition do Worker Assíncrono (ARQ / Ingestão)
resource "aws_ecs_task_definition" "worker" {
  family                   = "fin-worker-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "fin-worker"
      image     = var.worker_image
      essential = true

      command = ["python", "-m", "app.cli", "worker", "--burst", "false"]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "LOG_LEVEL", value = var.environment == "production" ? "INFO" : "DEBUG" },
        { name = "ARQ_MAX_JOBS", value = "20" }
      ]

      secrets = concat(
        var.database_url_secret_arn != "" ? [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }] : [],
        var.redis_url_secret_arn != "" ? [{ name = "REDIS_URL", valueFrom = var.redis_url_secret_arn }] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])

  tags = var.tags
}

# ----------------------------------------------------
# ECS SERVICES
# ----------------------------------------------------

# Serviço da API HTTP
resource "aws_ecs_service" "api" {
  name            = "fin-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_min_capacity
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.api_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "fin-api"
    container_port   = 8000
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Serviço do Worker ARQ
resource "aws_ecs_service" "worker" {
  name            = "fin-worker-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_min_capacity
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.worker_security_group_id]
    assign_public_ip = false
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ----------------------------------------------------
# AUTOSCALING (API)
# ----------------------------------------------------
resource "aws_appautoscaling_target" "api" {
  max_capacity       = var.api_max_capacity
  min_capacity       = var.api_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Escala por CPU (> 70%)
resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "fin-api-cpu-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Escala por Memória (> 75%)
resource "aws_appautoscaling_policy" "api_memory" {
  name               = "fin-api-mem-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

data "aws_region" "current" {}
