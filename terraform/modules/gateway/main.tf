# Application Load Balancer Público
resource "aws_lb" "main" {
  name               = "fin-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.environment == "production" ? true : false
  drop_invalid_header_fields = true

  tags = merge(
    var.tags,
    {
      Name        = "fin-alb-${var.environment}"
      Environment = var.environment
    }
  )
}

# Target Group da API HTTP (Porta 8000)
resource "aws_lb_target_group" "api" {
  name        = "fin-tg-api-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-tg-api-${var.environment}"
      Environment = var.environment
    }
  )
}

# Target Group para Webhooks (com timeout de resposta ligeiramente estendido)
resource "aws_lb_target_group" "webhooks" {
  name        = "fin-tg-webhooks-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(
    var.tags,
    {
      Name        = "fin-tg-webhooks-${var.environment}"
      Environment = var.environment
    }
  )
}

# Listener HTTP (Porta 80)
# Se houver certificado ACM, redireciona 80 -> 443; caso contrario, encaminha para o target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.api.arn
    }
  }

  tags = var.tags
}

# Listener HTTPS Seguro (Porta 443)
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = var.tags
}

# Regra de Roteamento para Webhooks (/billing/webhooks/*)
resource "aws_lb_listener_rule" "webhooks" {
  count        = var.certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webhooks.arn
  }

  condition {
    path_pattern {
      values = ["/billing/webhooks/*", "/v1/billing/webhooks/*"]
    }
  }
}
