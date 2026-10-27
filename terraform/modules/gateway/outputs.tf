output "alb_id" {
  description = "ID do Application Load Balancer"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ARN do Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS publico do Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Canonical Hosted Zone ID do ALB (para configuracao no Route53/Cloudflare)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ARN do Target Group da API"
  value       = aws_lb_target_group.api.arn
}

output "webhooks_target_group_arn" {
  description = "ARN do Target Group dos Webhooks"
  value       = aws_lb_target_group.webhooks.arn
}
