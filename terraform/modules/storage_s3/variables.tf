variable "environment" {
  description = "Ambiente de implantação (staging, production)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN da chave KMS para criptografia em repouso dos buckets"
  type        = string
}

variable "tags" {
  description = "Tags padrao"
  type        = map(string)
  default     = {}
}
