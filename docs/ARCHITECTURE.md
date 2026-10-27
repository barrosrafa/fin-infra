# Arquitetura de Infraestrutura & Plataforma — `fin-infra`

**Repositório:** `https://github.com/barrosrafa/fin-infra`  
**Escopo:** Terraform (IaC), CI/CD (GitHub Actions), Observabilidade (Prometheus/Grafana/Loki/OTel) e Configuração do Gateway (Ingress & Egress Anti-Bot).  
**Data:** 2026-10-26  

---

## 1. Visão Geral da Arquitetura

O `fin-infra` provê a camada de fundação em nuvem para sustentar todo o ecossistema `fin`:
1. **`fin-db`**: Banco de Dados PostgreSQL 18 / TimescaleDB no Neon Serverless (12 schemas, 303 tabelas, 36 hypertables, pgvector).
2. **`fin-api`**: Backend assíncrono em FastAPI + Uvicorn + ARQ Worker (cache-aside no Redis, stale-while-revalidate, autenticação Supabase, cobrança Asaas/Stripe).
3. **`fin-ingestion`**: Pipeline de coleta, parsing, landing em `raw.payload` e transformações dbt cobrindo 12 plataformas financeiras e 4 fontes oficiais.
4. **`fin-infra`**: A infraestrutura como código que conecta e orquestra tudo isso de forma segura, escalável e observável.

---

## 2. Topologia de Rede & Isolamento de Segurança (AWS)

```
                            INTERNET
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
   [Tráfego de Entrada]                  [Tráfego de Saída de Coleta]
 (Usuários Web / Mobile)               (12 Plataformas & Órgãos Oficiais)
            │                                     │
            ▼                                     ▲
┌─────────────────────────────────────────────────┴───────────────────────────────────────────────┐
│ VPC (10.0.0.0/16) — 3 Zonas de Disponibilidade (us-east-1a, 1b, 1c)                             │
│                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ SUBNETS PÚBLICAS (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)                                   │  │
│  │   • Internet Gateway                                                                      │  │
│  │   • Application Load Balancer (ALB) — TLS 1.3 / ACM Certificate                           │  │
│  │   • NAT Gateways (Multi-AZ para alta disponibilidade)                                     │  │
│  │   • Traefik Ingress Gateway / WAF Básico                                                  │  │
│  └───────────────────────────────┬───────────────────────────────────────────────────────────┘  │
│                                  │ Encaminha para Tasks Privadas                                │
│  ┌───────────────────────────────▼───────────────────────────────────────────────────────────┐  │
│  │ SUBNETS PRIVADAS DE COMPUTAÇÃO (10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24)                  │  │
│  │   • ECS Fargate Cluster (`fin-cluster`):                                                  │  │
│  │       - `fin-api` Service (FastAPI HTTP — Autoscaling por CPU/RPS)                        │  │
│  │       - `fin-worker` Service (ARQ Worker — Autoscaling por fila Redis)                     │  │
│  │       - `fin-ingestion` Scheduled Tasks / Cron                                             │  │
│  │   • Scraper Egress Gateway (Cluster Forward Proxy com rotação de IPs e perfis)            │  │
│  │   • OpenTelemetry Collector Task                                                          │  │
│  └───────────────────────────────┬───────────────────────────────────────────────────────────┘  │
│                                  │ Conexão Isolada Interna                                      │
│  ┌───────────────────────────────▼───────────────────────────────────────────────────────────┐  │
│  │ SUBNETS PRIVADAS DE DADOS & CACHE (10.0.50.0/24, 10.0.60.0/24, 10.0.70.0/24)              │  │
│  │   • AWS ElastiCache Redis 7+ (Multi-AZ, Automatic Failover, Transit/At-rest Encryption)   │  │
│  │   • VPC Endpoints: S3, ECR, CloudWatch Logs, Secrets Manager                              │  │
│  │   • Conector Seguro TLS 1.3 para PostgreSQL 18 / TimescaleDB no Neon Serverless           │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Os Quatro Pilares do `fin-infra`

### 3.1 Terraform (IaC Modular)
- **Modularidade Limpa**:
  - `modules/vpc`: Criação de VPC, subnets, NAT Gateways, VPC Endpoints, tabelas de roteamento e Flow Logs.
  - `modules/security`: Grupos de segurança com princípio do menor privilégio, IAM roles e chaves KMS de criptografia gerenciada.
  - `modules/database_cache`: Gestão do cluster Redis 7+ no ElastiCache e parametrização segura de conexão ao Neon PostgreSQL.
  - `modules/compute_ecs`: Cluster ECS Fargate, Task Definitions, CloudWatch Log Groups e políticas de autoscaling baseadas em CPU, memória e profundidade de fila do Redis.
  - `modules/gateway`: Load Balancer, listeners HTTP/HTTPS, regras de path routing e infraestrutura do Scraper Egress Gateway.
  - `modules/storage_s3`: Buckets S3 (landing de payloads brutos, artefatos dbt, logs de auditoria) com regras de ciclo de vida (transição para Glacier e expiração).
  - `modules/secrets`: AWS Secrets Manager e SSM Parameter Store com criptografia KMS.
- **Isolamento de Ambientes**:
  - `environments/staging` e `environments/production` compartilham os mesmos módulos com variáveis dimensionadas para cada ambiente.

### 3.2 CI/CD (GitHub Actions)
- **Pipelines Especializados e Seguros**:
  - `terraform.yml`: Validação sintática (`terraform fmt -check`), lint com `tflint`, auditoria com `trivy`, geração de plano no Pull Request e aplicação controlada no merge para `main` (com aprovação manual em produção).
  - `ci-cd-api.yml`: Lint (`ruff`), testes (`pytest`), build de imagem Docker multi-arch, push para o Amazon ECR e deploy rolling no ECS.
  - `ci-cd-ingestion.yml`: Validação de coletores e empacotamento de containers de coleta.
  - `ci-cd-db.yml`: Validação estrita e execução idempotente de migrações no Neon.
  - `security-scan.yml`: Varredura periódica de vulnerabilidades em dependências, imagens e detecção de credenciais vazadas com Gitleaks.

### 3.3 Observabilidade Unificada
- **Métricas (Prometheus & OpenTelemetry)**:
  - Instrumentação nativa FastAPI (`prometheus-fastapi-instrumentator`), métricas do Redis (memory, connected clients, queue depth), métricas do banco (conexões ativas, locks, transações por segundo) e métricas customizadas de coleta para os 12 sites.
- **Dashboards as Code (Grafana)**:
  - `fin-overview.json`: Panorama geral do sistema (RPS, latência p95, taxa de erros, consumo de recursos).
  - `fin-api-performance.json`: Desempenho detalhado de cada rota HTTP.
  - `fin-scrapers-rea-health.json`: Monitoramento em tempo real dos 12 scrapers (sucessos vs. HTTP 429/403, latência de resposta, status do circuit breaker).
  - `fin-db-timescaledb.json`: Saúde do Neon/TimescaleDB, tamanho dos chunks das 36 hypertables e cache hit ratio.
- **Logs Estruturados (Loki & Promtail)**:
  - Formato JSON padronizado com correlação direta via `trace_id` e `request_id`.
- **Alertas Proativos (Alertmanager)**:
  - Disparos automáticos para canais do Slack/Discord quando a taxa de erro de um scraper ultrapassar 10%, quando um circuit breaker abrir, ou quando a latência p95 da API exceder 50ms.

### 3.4 Configuração do Gateway (Ingress & Egress)
- **Ingress Gateway**:
  - Roteamento inteligente de rotas `/v1/*` para a API, `/billing/webhooks/*` com corpo cru e bypass de rate limit para IPs conhecidos de Asaas e Stripe, e endpoints administrativos fechados na VPC.
  - Rate limiting granular por IP e API Key usando algoritmo Token Bucket.
- **Scraper Egress Gateway**:
  - Roteamento seletivo de tráfego de saída baseado no alvo:
    - *Direct NAT*: Órgãos reguladores (B3, CVM, BCB) e APIs públicas leves.
    - *Datacenter Rotating*: Plataformas com Cloudflare padrão (Status Invest, Brick360).
    - *Sticky ISP*: Plataformas que exigem sessão e cookies consistentes (Investidor10, Fundamentus, Clube FII).
    - *Residential Rotating*: Plataformas com bloqueio agressivo CloudFront/Incapsula (Mais Retorno, ADVFN).
