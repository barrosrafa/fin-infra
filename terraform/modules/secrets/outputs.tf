output "app_secret_arn" {
  description = "ARN do segredo da aplicacao no Secrets Manager"
  value       = aws_secretsmanager_secret.app.arn
}

output "app_secret_id" {
  description = "ID do segredo da aplicacao no Secrets Manager"
  value       = aws_secretsmanager_secret.app.id
}
