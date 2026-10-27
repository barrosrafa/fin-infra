variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets publicas para o Application Load Balancer"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID do ALB"
  type        = string
}

variable "certificate_arn" {
  description = "ARN do certificado SSL/TLS no AWS Certificate Manager (ACM)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags padrao"
  type        = map(string)
  default     = {}
}
