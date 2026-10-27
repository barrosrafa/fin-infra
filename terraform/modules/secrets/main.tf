# Segredos da Aplicacao no Secrets Manager
resource "aws_secretsmanager_secret" "app" {
  name                    = "fin/${var.environment}/app-secrets"
  description             = "Credenciais e tokens de API da plataforma fin (${var.environment})"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = merge(
    var.tags,
    {
      Name        = "fin-app-secrets-${var.environment}"
      Environment = var.environment
    }
  )
}

# Template de valores de segredos inicializados com placeholders seguros
resource "aws_secretsmanager_secret_version" "app_template" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    SUPABASE_URL              = "https://your-project.supabase.co"
    SUPABASE_ANON_KEY         = "placeholder"
    SUPABASE_SERVICE_ROLE_KEY = "placeholder"
    SUPABASE_JWT_SECRET       = "placeholder"
    ASAAS_API_KEY             = "placeholder"
    STRIPE_SECRET_KEY         = "placeholder"
    STRIPE_WEBHOOK_SECRET     = "placeholder"
    RESIDENTIAL_PROXY_URL     = "placeholder"
    DATACENTER_PROXY_URL      = "placeholder"
    CLUBE_FII_JWT_SECRET      = "placeholder"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
