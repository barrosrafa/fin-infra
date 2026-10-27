.PHONY: help init plan apply destroy lint test-docker up down obs-up obs-down clean

help: ## Mostra comandos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ==========================================
# LOCAL DEVELOPMENT & DOCKER
# ==========================================
up: ## Inicia o ambiente local completo (API, Redis, Gateway, Proxies)
	docker compose up -d

down: ## Para o ambiente local completo
	docker compose down

obs-up: ## Inicia a stack de observabilidade (Prometheus, Grafana, Loki, Promtail, OTel)
	docker compose -f docker-compose.observability.yml up -d

obs-down: ## Para a stack de observabilidade
	docker compose -f docker-compose.observability.yml down

logs: ## Exibe logs de todos os containers
	docker compose logs -f

# ==========================================
# TERRAFORM COMMANDS
# ==========================================
ENV ?= staging

tf-init: ## Inicializa o Terraform para o ambiente selecionado (make tf-init ENV=staging)
	cd terraform/environments/$(ENV) && terraform init

tf-fmt: ## Formata e valida sintaxe dos arquivos Terraform
	terraform fmt -recursive terraform/

tf-lint: ## Executa o tflint em todos os módulos
	tflint --recursive terraform/

tf-validate: ## Valida a configuração do Terraform
	cd terraform/environments/$(ENV) && terraform validate

tf-plan: tf-fmt tf-validate ## Executa o terraform plan (make tf-plan ENV=staging)
	cd terraform/environments/$(ENV) && terraform plan -out=tfplan

tf-apply: ## Aplica o plano do terraform (make tf-apply ENV=staging)
	cd terraform/environments/$(ENV) && terraform apply tfplan

tf-destroy: ## Destroi os recursos provisionados (make tf-destroy ENV=staging)
	cd terraform/environments/$(ENV) && terraform destroy

# ==========================================
# SECURITY & QUALITY GATES
# ==========================================
sec-scan: ## Executa varredura de segurança com trivy
	trivy config terraform/
	trivy fs --security-checks vuln,secret,config .

clean: ## Limpa arquivos temporários e caches locais
	find . -type d -name ".terraform" -exec rm -rf {} +
	find . -type f -name "*.tfplan" -delete
	find . -type f -name "*.tfstate*" -delete
