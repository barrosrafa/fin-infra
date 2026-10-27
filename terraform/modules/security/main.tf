# Chave KMS Principal da Aplicação
resource "aws_kms_key" "main" {
  description             = "Chave KMS para criptografia gerenciada de dados do fin-infra (${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name        = "fin-kms-key-${var.environment}"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "main" {
  name          = "alias/fin-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# ----------------------------------------------------
# SECURITY GROUPS
# ----------------------------------------------------

# Security Group do Application Load Balancer (ALB)
resource "aws_security_group" "alb" {
  name        = "fin-sg-alb-${var.environment}"
  description = "Controle de acesso para o Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP de qualquer origem (redirecionado para HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS seguro de qualquer origem"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Saída liberada para encaminhamento interno"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-sg-alb-${var.environment}"
      Environment = var.environment
    }
  )
}

# Security Group da API HTTP (FastAPI)
resource "aws_security_group" "api" {
  name        = "fin-sg-api-${var.environment}"
  description = "Acesso restrito aos containers da API FastAPI"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Trafego HTTP apenas a partir do ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Saida irrestrita para comunicacao com Redis, Neon DB e servicos AWS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-sg-api-${var.environment}"
      Environment = var.environment
    }
  )
}

# Security Group dos Workers Assíncronos & Ingestion (ARQ / Scraping)
resource "aws_security_group" "worker" {
  name        = "fin-sg-worker-${var.environment}"
  description = "Security Group para Workers de tarefas ARQ e ingestao"
  vpc_id      = var.vpc_id

  # Sem ingress publico: o worker apenas consome filas e busca dados externos
  egress {
    description = "Saida irrestrita para acesso ao Redis, Neon DB e internet (via Egress Gateway/NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-sg-worker-${var.environment}"
      Environment = var.environment
    }
  )
}

# Security Group do Scraper Egress Gateway (Forward Proxy Cluster)
resource "aws_security_group" "egress_proxy" {
  name        = "fin-sg-egress-proxy-${var.environment}"
  description = "Controle de acesso para o cluster de forward proxy de scrapers"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Porta do proxy de scrapers acessivel apenas pelos workers"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  ingress {
    description     = "Porta Squid alternativa"
    from_port       = 3128
    to_port         = 3128
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    description = "Saida para pools de proxy externos e alvos de coleta"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-sg-egress-proxy-${var.environment}"
      Environment = var.environment
    }
  )
}

# Security Group do Redis (ElastiCache)
resource "aws_security_group" "redis" {
  name        = "fin-sg-redis-${var.environment}"
  description = "Acesso exclusivo ao cluster Redis a partir de API e Workers"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis port apenas da API"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  ingress {
    description     = "Redis port apenas dos Workers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    description = "Sem trafego de saida iniciado pelo Redis"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-sg-redis-${var.environment}"
      Environment = var.environment
    }
  )
}

# ----------------------------------------------------
# IAM ROLES & POLICIES (Menor Privilegio)
# ----------------------------------------------------

# ECS Task Execution Role (Permite ao agente ECS puxar imagens e gravar logs)
resource "aws_iam_role" "ecs_execution" {
  name = "fin-ecs-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_standard" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Politica customizada para descriptografar KMS e ler Secrets
resource "aws_iam_policy" "ecs_secrets_kms" {
  name        = "fin-ecs-secrets-kms-policy-${var.environment}"
  description = "Permite a Task Execution Role ler segredos e descriptografar via KMS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_secrets" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_secrets_kms.arn
}

# ECS Task Role (Permissoes concedidas a aplicacao em tempo de execucao)
resource "aws_iam_role" "ecs_task" {
  name = "fin-ecs-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })

  tags = var.tags
}

# Politica para a aplicacao gravar e ler dados do S3 (raw payloads, dbt)
resource "aws_iam_policy" "ecs_task_s3" {
  name        = "fin-ecs-task-s3-policy-${var.environment}"
  description = "Permite as aplicacoes acessar os buckets S3 do ecossistema fin"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::fin-*-${var.environment}",
          "arn:aws:s3:::fin-*-${var.environment}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_s3.arn
}
