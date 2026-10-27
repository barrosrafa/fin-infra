variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "tags" {
  description = "Tags padrão para os recursos"
  type        = map(string)
  default     = {}
}
