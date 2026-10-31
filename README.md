# 🌐 fin-infra — Infraestrutura em Nuvem, CI/CD, Observabilidade & Gateway

Repositório central de **Infraestrutura como Código (Terraform)**, **Pipelines de CI/CD (GitHub Actions)**, **Stack de Observabilidade Unificada (Prometheus, Grafana, Loki, OTel)** e **Gateway de Entrada (Ingress) e Saída (Egress Anti-Bot)** para a plataforma do ecossistema **`fin`**.

- **Repositório:** `https://github.com/barrosrafa/fin-infra`
- **Banco de Dados Relacionado:** `https://github.com/barrosrafa/fin-db` (PostgreSQL 18 / TimescaleDB no Neon)
- **API & Worker:** `https://github.com/barrosrafa/fin-api` (FastAPI / ARQ / Redis)
- **Ingestão & dbt:** `https://github.com/barrosrafa/fin-ingestion` (Scrapers REA & Pipelines)
- **Frontend Web:** `https://github.com/barrosrafa/fin-web` (Next.js 16 / React 19)
- **Deploy Distribuído Gratuito:** [`koyeb.yaml`](koyeb.yaml) | [`scripts/verify_cloud_deploy.py`](scripts/verify_cloud_deploy.py)
- **Especificação REA & Gateway:** [`docs/REA_ANALYSIS_AND_GATEWAY_SPEC.md`](docs/REA_ANALYSIS_AND_GATEWAY_SPEC.md)
- **Gateway de API para previews:** [`docker-compose.staging-gateway.yml`](docker-compose.staging-gateway.yml) | [`gateway/staging/`](gateway/staging/)
- **Documento Arquitetural:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

---

## 🏛️ Visão Geral da Arquitetura

O `fin-infra` conecta os componentes do ecossistema através de uma arquitetura resiliente na AWS, projetada com separação rigorosa de camadas e isolamento de segurança:

```
                            TRÁFEGO DE ENTRADA (INGRESS)
                            ┌──────────────────────────┐
                            │  Clientes (Web / Mobile) │
                            └─────────────┬────────────┘
                                          │ HTTPS / TLS 1.3
                                          ▼
                            ┌──────────────────────────┐
                            │ Application Load Balancer│
                            │  + Traefik / Nginx WAF   │
                            └─────────────┬────────────┘
                                          │ Encaminhamento Interno
                     ┌────────────────────┴────────────────────┐
                     ▼                                         ▼
      ┌─────────────────────────────┐           ┌─────────────────────────────┐
      │     /api/v1/* (Público)     │           │/billing/webhooks/* (Webhook)│
      │  Rate Limit: 120 req/min/IP │           │ Bypass de Rate Limit p/ IPs │
      │  JWT Bearer (Supabase)      │           │ Asaas / Stripe (Assin. HMAC)│
      └──────────────┬──────────────┘           └──────────────┬──────────────┘
                     │                                         │
                     └────────────────────┬────────────────────┘
                                          │
                                          ▼
                            ┌──────────────────────────┐
                            │  FIN-API (ECS Fargate)   │
                            │ FastAPI + Uvicorn Async  │
                            └──────┬────────────┬──────┘
                                   │            │
            Leitura / Escrita      │            │ Tarefas / Warm-up
                                   ▼            ▼
      ┌──────────────────────────────┐   ┌──────────────────────────────┐
      │     POSTGRESQL 18 / NEON     │   │       REDIS 7+ CLUSTER       │
      │ TimescaleDB (36 Hypertables) │   │ • Cache de Cotações / Múltiplos│
      │ pgvector (Busca Semântica)   │   │ • Filas ARQ (high, default)  │
      │ 12 Schemas, 303 Tabelas      │   │ • Circuit Breakers / Tokens  │
      └──────────────────────────────┘   └──────────────┬───────────────┘
                                                        │ Consumo de Fila
                                                        ▼
                                         ┌──────────────────────────────┐
                                         │  FIN-WORKER / FIN-INGESTION  │
                                         │        (ECS Fargate)         │
                                         └──────────────┬───────────────┘
                                                        │ Scraping / Coleta
                                                        ▼
                            TRÁFEGO DE SAÍDA (EGRESS ANTI-BOT)
                            ┌──────────────────────────────────────────┐
                            │         SCRAPER EGRESS GATEWAY           │
                            │     (Forward Proxy Cluster / Squid)      │
                            │                                          │
                            │ • TLS JA3/JA4 Fingerprint Emulation      │
                            │ • User-Agent & Headers de Navegador      │
                            │ • Smart Domain Router:                   │
                            │   - Direct NAT: B3, CVM, BCB, ETFsBrasil │
                            │   - Datacenter: StatusInvest, Brick360   │
                            │   - Sticky ISP: Investidor10, Fundamentus│
                            │   - Residential: MaisRetorno, ADVFN      │
                            └─────────────────────┬────────────────────┘
                                                  │
                                                  ▼
                               [12 Plataformas & Órgãos Reguladores]
```

---

## ⚡ Os 4 Pilares do `fin-infra`

### Gateway enxuto para Preview → API de Staging

`docker-compose.staging-gateway.yml` inicia um Nginx isolado que aceita somente `/api/v1/*`, aplica limite de 15 req/s por IP e encaminha para o hostname HTTPS da API de staging. `/healthz` verifica `/health` no upstream. O serviço escuta em `127.0.0.1:8088` por padrão, para ser publicado via Cloudflare Tunnel ou ingress já confiável; não expõe porta diretamente à internet.

1. Defina `API_STAGING_HOST` com o hostname da API de staging (sem esquema, porta ou caminho) e `API_STAGING_GATEWAY_PORT` se necessário, em um arquivo de ambiente local não versionado.
2. Suba apenas essa camada: `docker compose --env-file .env.staging -f docker-compose.staging-gateway.yml up -d --build`.
3. Publique `/api/v1/*` e `/healthz` do gateway por HTTPS em um hostname dedicado. No deployment **Preview** do `fin-web`, aponte `API_BACKEND_URL` para essa origem HTTPS. Mantenha `API_BACKEND_URL` de produção separado no ambiente **Production**.

O gateway não configura credenciais da API nem acessa Neon; a aplicação Next encaminha o tráfego e o CMS usa uma conexão de staging independente descrita no README do `fin-web`.

### 1. Terraform (Infraestrutura como Código)
Estrutura modular limpa e validada:
- **`modules/vpc`**: VPC com 3 zonas de disponibilidade (us-east-1a, 1b, 1c), subnets públicas, privadas de computação e isoladas de banco/cache, NAT Gateways e Gateway Endpoint para S3.
- **`modules/security`**: Menor privilégio com Security Groups segregados (ALB, API, Worker, Redis, Proxy), IAM Roles para ECS Fargate e chaves KMS para criptografia em repouso.
- **`modules/database_cache`**: Cluster AWS ElastiCache Redis 7+ com Multi-AZ, failover automático, criptografia em trânsito e at-rest, auth token e integração Neon PostgreSQL 18.
- **`modules/compute_ecs`**: Cluster ECS Fargate com Container Insights, task definitions para `fin-api` e `fin-worker` com autoscaling baseado em CPU, memória e profundidade de fila.
- **`modules/gateway`**: Application Load Balancer com listener HTTPS (TLS 1.3), certificados ACM e regras de path routing.
- **`modules/storage_s3`**: Buckets S3 com versionamento, criptografia SSE-KMS e regras de ciclo de vida (transição para Standard-IA aos 90 dias, Glacier aos 180 dias).
- **`modules/secrets`**: AWS Secrets Manager e SSM Parameter Store gerenciados com chaves KMS.
- **`environments/`**: Ambientes isolados `staging` e `production`.

### 2. CI/CD (GitHub Actions)
- **`terraform.yml`**: Formatação (`terraform fmt -check`), lint com `tflint`, auditoria com `trivy`, plano em pull request e aplicação automática em `main` com aprovação manual em produção.
- **`ci-cd-api.yml`**: Pipeline para `fin-api` com lint (`ruff`), testes (`pytest`), build de imagem Docker e rolling deploy no ECS.
- **`ci-cd-ingestion.yml`**: Validação de coletores dos 12 sites REA e dbt models.
- **`ci-cd-db.yml`**: Validação de migrações e teste de idempotência no PostgreSQL 18.
- **`security-scan.yml`**: Detecção de segredos com Gitleaks e auditoria periódica de vulnerabilidades de dependências.

### 3. Observabilidade Unificada
- **OpenTelemetry Collector**: Pipelines unificadas de métricas, traces e logs.
- **Prometheus**: Scrape centralizado de `fin-api`, `fin-worker`, `redis-exporter`, `postgres-exporter` e `scraper-egress-gateway`.
- **Alertmanager**: Disparo de alertas críticos para canais do Slack e Discord:
  - `ScraperCircuitBreakerOpen`: Circuito aberto após 5 falhas consecutivas em uma fonte.
  - `ScraperRateLimitSpike`: Pico de HTTP 429 por domínio alvo.
  - `ApiHighLatency`: Tempo de resposta p95 superior a 50ms.
  - `ApiErrorRateHigh`: Erros HTTP 5xx superiores a 1%.
  - `RedisMemoryHigh`: Consumo de memória do Redis superior a 80%.
- **Grafana (Dashboards as Code)**:
  1. `fin-overview.json`: Saúde global, throughput (RPS), latência p95 e status codes.
  2. `fin-api-performance.json`: Latência por endpoint e taxa de acerto de cache (*Cache Hit Ratio*).
  3. `fin-scrapers-rea-health.json`: **Painel exclusivo para as 12 plataformas REA**, monitorando circuit breakers, sucessos vs. HTTP 429/403, latência de scraping e pools de proxy ativos.
  4. `fin-db-timescaledb.json`: Sessões ativas, TPS, buffer hit ratio e tamanho do banco.
- **Loki & Promtail**: Coleta e indexação de logs estruturados em JSON com correlação por `trace_id`.

### 4. Configuração do Gateway
- **Ingress Gateway (Traefik & Nginx)**:
  - Terminação TLS 1.3 com headers de segurança (HSTS, CSP, X-Frame-Options).
  - Rate limiting por Token Bucket (120 req/min anônimo/free, 600 req/min pro).
  - Roteamento `/billing/webhooks/*` preservando payload binário cru para validação de assinatura HMAC do Asaas e Stripe.
- **Scraper Egress Gateway (Forward Proxy & Smart Rotator)**:
  - Roteador inteligente de saída projetado para mitigar bloqueios de Cloudflare, Turnstile, LiteSpeed e rate limits nos 12 sites mapeados no REA:
    - **Perfil 1 (Direct NAT):** B3, CVM, BCB, ETFs Brasil.
    - **Perfil 2 (Datacenter Rotating):** Status Invest, Fundamentei, Brick360, Funds Explorer.
    - **Perfil 3 (Sticky Session ISP):** Investidor10, Fundamentus, Clube FII.
    - **Perfil 4 (Residential Rotating):** Mais Retorno, ADVFN Brasil.
  - Injeção de headers de navegador (`Sec-Ch-Ua`, `User-Agent`) e emulação TLS JA3/JA4.
  - Circuit Breakers em memória e Redis para resfriamento automático de IPs bloqueados.

---

## 🚀 Execução Local Rápida

### Pré-requisitos
- Docker & Docker Compose
- Make

### Iniciar o Ambiente Local Completo
```bash
# Clone o repositório
git clone https://github.com/barrosrafa/fin-infra.git
cd fin-infra

# Configure as variáveis de ambiente
cp .env.example .env

# Inicie o Gateway, Redis e Scraper Proxy
make up

# Inicie a Stack de Observabilidade (Prometheus, Grafana, Loki, Alertmanager, OTel)
make obs-up
```

### URLs Locais de Acesso
| Serviço | URL | Credenciais Padrão |
|---|---|---|
| **Traefik Dashboard** | `http://localhost:8080` | Aberto localmente |
| **Grafana** | `http://localhost:3000` | `admin` / `admin` |
| **Prometheus** | `http://localhost:9090` | Aberto localmente |
| **Alertmanager** | `http://localhost:9093` | Aberto localmente |
| **Scraper Egress Metrics** | `http://localhost:9091/metrics` | Métricas em tempo real |
| **Squid Forward Proxy** | `localhost:3128` | Proxy interno |

---

## 🛠️ Comandos do Makefile

```bash
make help          # Exibe lista de comandos disponíveis
make up            # Inicia containers da aplicação e proxies
make down          # Para os containers da aplicação
make obs-up        # Inicia Prometheus, Grafana, Loki e OTel
make obs-down      # Para a stack de observabilidade
make tf-fmt        # Formata arquivos Terraform recursivamente
make tf-plan       # Executa o terraform plan para staging
make tf-apply      # Aplica a infraestrutura no ambiente configurado
make sec-scan      # Executa varredura de segurança com Trivy
```

---

## 📂 Estrutura do Repositório

```
fin-infra/
├── docs/
│   ├── ARCHITECTURE.md                  # Especificação arquitetural completa
│   └── REA_ANALYSIS_AND_GATEWAY_SPEC.md # Análise dos 12 sites REA e requisitos de gateway
├── terraform/
│   ├── modules/
│   │   ├── vpc/                         # VPC, subnets multi-AZ, NAT Gateways, Endpoints
│   │   ├── security/                    # Security Groups, IAM Roles, Chaves KMS
│   │   ├── database_cache/              # ElastiCache Redis 7+ e integração Neon PostgreSQL
│   │   ├── compute_ecs/                 # ECS Fargate, Task Definitions, Autoscaling
│   │   ├── gateway/                     # ALB, listeners HTTPS, regras de roteamento
│   │   ├── storage_s3/                  # Buckets S3 (raw payloads, dbt, backups)
│   │   └── secrets/                     # AWS Secrets Manager e SSM Parameter Store
│   └── environments/
│       ├── staging/                     # Definição e variáveis de Staging
│       └── production/                  # Definição e variáveis de Produção
├── gateway/
│   ├── traefik/
│   │   ├── traefik.yml                  # Configuração estática do Traefik v3
│   │   └── dynamic_conf.yml             # Roteadores, middlewares e rate limiting
│   ├── nginx/
│   │   ├── nginx.conf                   # Configuração Nginx de alta performance
│   │   └── conf.d/fin.conf              # Virtual hosts e proxy pass de webhooks
│   └── egress_proxy/
│       ├── squid.conf                   # Squid forward proxy com anonimização
│       └── proxy_rotator.py             # Smart Router para os 12 sites REA
├── observability/
│   ├── otel-collector/
│   │   └── otel-collector-config.yaml   # Pipeline OTel para traces, métricas e logs
│   ├── prometheus/
│   │   ├── prometheus.yml               # Scrapes configurados
│   │   └── alerts/                      # Regras de alerta (Scrapers REA, API, Infra)
│   ├── grafana/
│   │   ├── provisioning/                # Datasources e dashboards provisionados
│   │   └── dashboards/                  # 4 Dashboards em JSON (Overview, API, REA, DB)
│   ├── loki/
│   │   └── loki-config.yaml             # Configuração do cluster Loki
│   ├── promtail/
│   │   └── promtail-config.yaml         # Coletor de logs do Docker
│   └── alertmanager/
│       └── alertmanager.yml             # Rotas de alerta para Slack e Discord
├── .github/
│   └── workflows/
│       ├── terraform.yml                # Lint, format, scan e plan/apply do Terraform
│       ├── ci-cd-api.yml                # CI/CD da API FastAPI e Worker ARQ
│       ├── ci-cd-ingestion.yml          # CI/CD de coletores e dbt models
│       ├── ci-cd-db.yml                 # Validação de migrações no Neon DB
│       └── security-scan.yml            # Gitleaks e Trivy security audit
├── docker-compose.yml                   # Stack local de API, Gateway e Proxies
├── docker-compose.observability.yml     # Stack local de observabilidade
├── Makefile                             # Automação de tarefas de desenvolvimento
├── .env.example                         # Template de variáveis de ambiente
├── .gitignore                           # Exclusões do Git
├── koyeb.yaml                           # Manifesto declarativo de deploy no Koyeb (Free Nano)
└── README.md                            # Guia principal de uso
```

---

## 🚀 Arquitetura Distribuída 100% Gratuita (Free Tier)

Para disponibilizar o ecossistema com acesso público 24/7 sem nenhum custo de infraestrutura:

| Componente | Provedor | Plano | Configuração / Endpoint |
|---|---|---|---|
| **fin-web** | **Vercel** | Hobby ($0) | [https://fin-web-wheat.vercel.app](https://fin-web-wheat.vercel.app) |
| **fin-api** | **Render** | Free ($0) | [https://fin-api-jbrz.onrender.com](https://fin-api-jbrz.onrender.com) |
| **fin-db** | **Neon** | Free Tier ($0) | PostgreSQL 18 Serverless com TimescaleDB e pgvector |
| **Redis** | **Managed** | Free Tier ($0) | Fila de mensagens e cache com fallback de resiliência |
| **fin-ingestion** | **GitHub Actions** | 2.000 min/mês ($0) | Workflows cron no pregão da B3, fechamento e fins de semana |

### Testando a Conectividade Remota
```bash
python scripts/verify_cloud_deploy.py --api-url https://fin-api-jbrz.onrender.com --web-url https://fin-web-wheat.vercel.app
```


## Estado operacional verificado em 29/10/2026

O destino de produção identificado é o serviço Docker gerenciado `fin-api` no **Render Free**, junto a Vercel, Neon e Upstash. O projeto Render consultado contém apenas esse serviço. O plano Free não oferece shell/SSH e não constitui um host com Docker Engine administrável para executar estes arquivos Compose. Nenhum servidor separado de Traefik foi identificado; os manifests não foram apresentados como aplicados nesse ambiente.

A CI `compose.yml` valida a interpolação do Compose e inicia contêineres descartáveis para verificar os parsers reais do Traefik v3.0 e Nginx. Isso é validação de configuração, não deploy de infraestrutura. Portas de Redis, proxy de saída, métricas e administração estão limitadas a loopback no host, e `REDIS_PASSWORD` deve ser fornecida explicitamente.

Para aplicar a stack em um servidor real, é necessário primeiro definir o host autorizado, o acesso SSH/Docker, o diretório dos repositórios e os domínios/certificados de TLS. Não apontar o Compose para o serviço Render, nem substituir sua imagem por Traefik: isso não fornece um Docker daemon e interromperia a API. Não foi contratado ou provisionado um servidor pago nesta operação.
