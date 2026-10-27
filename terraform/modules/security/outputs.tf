output "kms_key_arn" {
  description = "ARN da chave KMS principal"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "ID da chave KMS principal"
  value       = aws_kms_key.main.key_id
}

output "alb_security_group_id" {
  description = "Security Group ID do ALB"
  value       = aws_security_group.alb.id
}

output "api_security_group_id" {
  description = "Security Group ID da API FastAPI"
  value       = aws_security_group.api.id
}

output "worker_security_group_id" {
  description = "Security Group ID dos Workers ARQ / Ingestion"
  value       = aws_security_group.worker.id
}

output "egress_proxy_security_group_id" {
  description = "Security Group ID do Scraper Egress Gateway"
  value       = aws_security_group.egress_proxy.id
}

output "redis_security_group_id" {
  description = "Security Group ID do Redis ElastiCache"
  value       = aws_security_group.redis.id
}

output "ecs_execution_role_arn" {
  description = "ARN da ECS Task Execution Role"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN da ECS Task Runtime Role"
  value       = aws_iam_role.ecs_task.arn
}
