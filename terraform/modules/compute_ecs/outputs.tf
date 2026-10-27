output "cluster_id" {
  description = "ID do cluster ECS"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "Nome do cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "api_service_name" {
  description = "Nome do servico da API no ECS"
  value       = aws_ecs_service.api.name
}

output "worker_service_name" {
  description = "Nome do servico do Worker no ECS"
  value       = aws_ecs_service.worker.name
}
