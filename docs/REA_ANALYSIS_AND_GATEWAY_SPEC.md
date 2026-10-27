# REA — Reverse Engineering Analysis dos 12 Sites & Especificação do Gateway e Infraestrutura

**Projeto:** `fin-infra` (`https://github.com/barrosrafa/fin-infra`)  
**Ecosistema:** `fin-db` (PostgreSQL 18 / TimescaleDB no Neon), `fin-api` (FastAPI / ARQ), `fin-ingestion` (Pipelines de Coleta / dbt)  
**Data:** 2026-10-26  
**Versão:** 1.0  

---

## 1. Visão Geral e Intenção do Documento

Este documento consolida a **Engenharia Reversa Analítica (REA)** realizada sobre as **12 principais plataformas brasileiras de análise de investimentos** e os **4 órgãos reguladores oficiais**, detalhando suas tecnologias, padrões de comunicação, mecanismos de proteção contra bots e restrições de rede.

A partir desse diagnóstico, estabelecemos a **especificação arquitetural da infraestrutura (`fin-infra`)**, definindo o dimensionamento do **Egress Gateway de Scrapers**, a rotação de proxies, as regras de rate limiting, os circuitos de proteção (*circuit breakers*), a observabilidade em tempo real e o isolamento seguro de rede via **Terraform**.

---

## 2. Matriz Geral de REA das 12 Plataformas e 4 Órgãos Reguladores

| # | Fonte / Alvo | URL Base | Stack / Arquitetura | Mecanismos Anti-Bot / WAF | Sessão / Cookies | Estratégia de Egress Gateway |
|---|---|---|---|---|---|---|
| **OF1** | **B3** | `b3.com.br` | Posicional BVBG/COTAHIST, JSON Proxy | Akamai Edge / Aberto para dados públicos | Não | Datacenter Egress (Direct NAT) |
| **OF2** | **CVM** | `dados.cvm.gov.br` | HTTP Open Data (ZIP/CSV) | Sem WAF restritivo | Não | Datacenter Egress (Direct NAT) |
| **OF3** | **BCB** | `api.bcb.gov.br` | REST SGS / OData Olinda | Sem WAF restritivo | Não | Datacenter Egress (Direct NAT) |
| **OF4** | **ANBIMA** | `anbima.com.br` | Feeds TXT/Delimitado / HTML | Validação de Referer e sessão transitória | Transitório | Datacenter Egress com pool rotativo |
| **S01** | **Status Invest** | `statusinvest.com.br` | ASP.NET Core MVC + XHR | Cloudflare Bot Management (JA3/User-Agent) | Opcional | Rotating Datacenter / ISP Proxy + Emulação Browser |
| **S02** | **Investidor10** | `investidor10.com.br` | Laravel 10 + REST + Inline JS | Cloudflare + CSRF token + Session Cookies | Obrigatório (Sessão) | Sticky Session Proxy + Headers `X-Requested-With` |
| **S03** | **Fundamentei** | `fundamentei.com` | Next.js SSR + Apollo GraphQL | Cloudflare Turnstile (Login); JSON público SSR | Opcional | Rotating Proxy + AST Parsing de `__NEXT_DATA__` |
| **S04** | **Fundamentus** | `fundamentus.com.br` | PHP Clássico / LiteSpeed Server | Rate Limit por IP (>5 req/s = 403), Cookies `_uac` | Obrigatório (Cookies) | Sticky ISP Proxy + Delay inter-request + Latin-1 |
| **S05** | **Clube FII** | `clubefii.com.br` | ASP.NET MVC + GraphQL CR Data | JWT Bearer, validação estrita de `Origin` | Obrigatório (JWT) | Dedicated Egress + Refresh token automático |
| **S06** | **Funds Explorer**| `fundsexplorer.com.br` | WordPress Headless + AJAX | Cloudflare WAF + Nonce AJAX transitório | Sessão transitória | Rotating Datacenter Proxy + Cookie jar |
| **S07** | **FIIs.com.br** | `fiis.com.br` | WP Sage + Vue 3 Client Islands | Cloudflare CDN Cache | Não | Fast Direct Egress + Parsing de ilhas Vue 3 |
| **S08** | **Mais Retorno** | `maisretorno.com` | Next.js + Microserviços REST | AWS CloudFront Rate Limit por IP (HTTP 429) | Token transitório | Rotating Residential Proxy + Token Bucket |
| **S09** | **Análise de Ações**| `analisedeacoes.com` | Gatsby SSG + API REST v2 | Cloudflare CDN + Validação de Referer | Opcional | Direct Egress para `page-data` + Rotating para v2 |
| **S10** | **Brick360** | `brick360.com.br` | Vue 3 SPA + REST API v2 | Cloudflare + Bearer Token / API pública v2 | Opcional | Datacenter Proxy com timeout 15s |
| **S11** | **ADVFN Brasil** | `br.advfn.com` | Multi-bolsa SSR + AJAX | Incapsula / Cloudflare + Cookies de Tracking | Obrigatório | Rotating ISP/Residential Proxy + Browser Headers |
| **S12** | **ETFs Brasil** | `etfsbrasil.com.br` | Next.js Frontend + FastAPI | API pública CORS aberto | Não | Direct Egress (Sem proxy necessário) |

---

## 3. Análise Detalhada dos 12 Sites e Requisitos de Rede

### 3.1 Status Invest (`https://statusinvest.com.br`)
* **Padrão de Chamada:** Endpoints XHR JSON assíncronos (`/acao/tickerprice`, `/acao/getdre`, `/category/borrowhistory`, `/fii/cridetail`).
* **Desafio de Rede:** Cloudflare analisa a consistência entre o `User-Agent`, a versão do protocolo HTTP (exige HTTP/2) e o handshake TLS (cifras JA3/JA4). Se o coletor utilizar a assinatura padrão de bibliotecas como `urllib` ou `requests` sem customização, a conexão é descartada com HTTP 403.
* **Solução no Gateway:**
  - Injeção obrigatória dos headers `Sec-Ch-Ua`, `Sec-Ch-Ua-Mobile: ?0`, `Sec-Ch-Ua-Platform: "macOS"`.
  - HTTP/2 obrigatório via `httpx` com ALPN negociado.
  - Pool de proxies datacenter com rotação a cada 50 requisições.

### 3.2 Investidor10 (`https://investidor10.com.br`)
* **Padrão de Chamada:** Endpoints REST internos (`/api/historico-indicadores/{TICKER}/anual/`, `/api/balancos/{TICKER}/`) e arrays inline em scripts HTML.
* **Desafio de Rede:** A rota REST exige cookies de sessão prévios gerados na visita à página principal (`/acoes/{TICKER}/`) e o cabeçalho `X-Requested-With: XMLHttpRequest`.
* **Solução no Gateway:**
  - Sessão persistente (*Sticky Session*) no proxy para manter o mesmo IP entre a navegação na página principal e o fetch do endpoint REST correspondente.
  - Rate limit de 30 requisições/minuto por worker.

### 3.3 Fundamentei (`https://fundamentei.com`)
* **Padrão de Chamada:** Estado serializado no HTML em `window.__NEXT_DATA__.props.pageProps.apolloState.data`.
* **Desafio de Rede:** O login é protegido por Cloudflare Turnstile. Porém, páginas de emissores públicos expõem mais de 100 indicadores, segmentos de negócio e governança no HTML inicial.
* **Solução no Gateway:**
  - Requisição GET direta da página pública com parser JSON do DOM (sem renderização headless de browser pesada).
  - Proxy rotativo leve com compressão `br` (Brotli) ou `gzip` para minimizar consumo de banda.

### 3.4 Fundamentus (`https://fundamentus.com.br`)
* **Padrão de Chamada:** Requisições GET com query string em arquivos PHP (`detalhes.php?papel=...`, `resultado.php`, `fii_imoveis_detalhes.php`).
* **Desafio de Rede:** Servidor LiteSpeed com codificação `ISO-8859-1` e bloqueio agressivo de taxa: disparos acima de 5 requisições por segundo a partir do mesmo IP resultam em banimento temporário de 15 minutos (HTTP 403). Exige cookies de sessão (`_uac`, `_qn`).
* **Solução no Gateway:**
  - **Token Bucket estrito:** Máximo de 2 requisições por segundo por nó de coleta.
  - Circuit breaker configurado para pausar por 15 minutos se receber HTTP 403.
  - Tratamento de charset Latin-1 / ISO-8859-1 antes do parsing de HTML.

### 3.5 Clube FII (`https://www.clubefii.com.br`)
* **Padrão de Chamada:** GraphQL API (`https://api.clubefii.dev.br/graphql`) e rotas AJAX legadas ASP.NET.
* **Desafio de Rede:** A API GraphQL valida `Origin: https://www.clubefii.com.br` e `Referer`, exigindo JWT Bearer para consultas avançadas de transações imobiliárias e dados de mercado SiiLA.
* **Solução no Gateway:**
  - Gerenciamento de token de autenticação armazenado no Redis com renovação automática 30 minutos antes do vencimento (TTL 12h).
  - Cabeçalhos de CORS e Origin injetados de forma determinística.

### 3.6 Funds Explorer (`https://www.fundsexplorer.com.br`)
* **Padrão de Chamada:** AJAX REST customizado no WordPress (`/wp-json/funds-explorer/v1/funds-get-income`, `/ranking`).
* **Desafio de Rede:** Exige validação de WAF Cloudflare e nonce do WordPress extraído da tag de script da página principal.
* **Solução no Gateway:**
  - Coletor em duas etapas: extração do nonce e disparo de chamadas subsequentes dentro da mesma sessão de proxy.
  - Concorrência limitada a 5 workers paralelos.

### 3.7 FIIs.com.br (`https://fiis.com.br`)
* **Padrão de Chamada:** Ilhas Vue 3 (`data-island="invest-simulator"`) e rotas de agenda (`/agenda-de-dividendos/`).
* **Desafio de Rede:** Baixo bloqueio ativo, mas CDN Cloudflare agressiva com cache de borda.
* **Solução no Gateway:**
  - Requisição direta via egress padrão com `Cache-Control: no-cache` para evitar consumir páginas desatualizadas em datas de corte de proventos.

### 3.8 Mais Retorno (`https://maisretorno.com`)
* **Padrão de Chamada:** Microserviços REST em `data.maisretorno.com` (CVM 175, CDA) e `ms.maisretorno.com` (10 janelas de risco).
* **Desafio de Rede:** AWS CloudFront com rate limit por IP estrito. Varreduras em lote disparam HTTP 429 rapidamente.
* **Solução no Gateway:**
  - **Pool de Proxies Residenciais/Móveis Rotativos:** Cada lote de 10 consultas de fundos utiliza um IP distinto.
  - Retry com backoff exponencial truncado (2s, 4s, 8s, 16s) e jitter de até 500ms.

### 3.9 Análise de Ações (`https://www.analisedeacoes.com`)
* **Padrão de Chamada:** Arquivos JSON estáticos do Gatsby (`/page-data/*/page-data.json`) e API v2 em `api.analisedeacoes.com`.
* **Desafio de Rede:** Os arquivos `page-data.json` são estáticos e servidos em CDN sem proteção ativa. A API v2 requer cabeçalho `Referer: https://www.analisedeacoes.com/`.
* **Solução no Gateway:**
  - Priorizar a coleta via arquivos estáticos `page-data.json`, reduzindo em 90% a necessidade de chamar a API v2.

### 3.10 Brick360 (`https://brick360.com.br`)
* **Padrão de Chamada:** REST API v2 (`/api/v2/funds/{TICKER}/analysis/advanced`) com 12 módulos analíticos.
* **Desafio de Rede:** Payloads JSON grandes (até 800KB por fundo com DRE trimestral, imóveis e scoring). Timeouts prematuros podem corromper a ingestão.
* **Solução no Gateway:**
  - Timeout de leitura estendido no gateway para 30 segundos.
  - Compressão de resposta `gzip` ativada.

### 3.11 ADVFN Brasil (`https://br.advfn.com`)
* **Padrão de Chamada:** Rotas de análise técnica (`/suporte-e-resistencia/`, `/indicadores-de-preco/`, `/analise-tecnica/candlestick/`).
* **Desafio de Rede:** WAF da Incapsula/Imperva que detecta automação por verificação de cookies e fingerprinting TCP/TLS.
* **Solução no Gateway:**
  - Egress via pool de proxies residenciais com rotação por sessão.
  - Respeito a cookies de sessão e headers completos de navegador.

### 3.12 ETFs Brasil (`https://www.etfsbrasil.com.br`)
* **Padrão de Chamada:** Backend FastAPI nativo (`/api/backend/home`, `/api/backend/compare`, `/api/backend/etf/{TICKER}/composition`).
* **Desafio de Rede:** Sem proteções anti-bot restritivas, CORS liberado.
* **Solução no Gateway:**
  - Egress direto da VPC sem intermediários de proxy, alcançando latências inferiores a 50ms.

---

## 4. Arquitetura da Infraestrutura (`fin-infra`)

O diagrama abaixo ilustra a integração completa entre o tráfego de entrada de clientes (Ingress) e o tráfego de coleta de dados externos (Egress):

```
                                  TRÁFEGO DE ENTRADA (INGRESS)
                               ┌────────────────────────────────┐
                               │     CLIENTES (Web / Mobile)    │
                               └───────────────┬────────────────┘
                                               │ HTTPS / TLS 1.3
                                               ▼
                               ┌────────────────────────────────┐
                               │  APPLICATION LOAD BALANCER /   │
                               │        API GATEWAY (WAF)       │
                               └───────────────┬────────────────┘
                                               │
                        ┌──────────────────────┴──────────────────────┐
                        ▼                                             ▼
         ┌───────────────────────────────┐             ┌───────────────────────────────┐
         │     /api/v1/* (Público)       │             │ /billing/webhooks/* (Webhook) │
         │  Rate Limit: 120 req/min/IP   │             │  Rate Limit: Bypass p/ IPs    │
         │  JWT Auth Bearer (Supabase)   │             │  Asaas / Stripe com HMAC      │
         └──────────────┬────────────────┘             └──────────────┬────────────────┘
                        │                                             │
                        └──────────────────────┬──────────────────────┘
                                               │
                                               ▼
                               ┌────────────────────────────────┐
                               │      FIN-API (ECS Fargate)     │
                               │    FastAPI + Uvicorn Async     │
                               └───────┬────────────────┬───────┘
                                       │                │
            Leitura / Escrita Canônica │                │ Tarefas de Ingestão / Warm-up
                                       ▼                ▼
         ┌───────────────────────────────┐   ┌─────────────────────────────────────────┐
         │     POSTGRESQL 18 / NEON      │   │             REDIS 7+ CLUSTER            │
         │   TimescaleDB (36 Hypertables)│   │  • Cache de Cotações e Indicadores      │
         │   pgvector (Busca Semântica)  │   │  • Filas ARQ (high, default, batch)     │
         │   12 Schemas, 303 Tabelas     │   │  • Circuit Breakers & Token Buckets     │
         └───────────────────────────────┘   └────────────────────┬────────────────────┘
                                                                  │
                                                                  │ Consumo de Tarefas
                                                                  ▼
                                             ┌─────────────────────────────────────────┐
                                             │       FIN-WORKER / FIN-INGESTION        │
                                             │               (ECS Fargate)             │
                                             └────────────────────┬────────────────────┘
                                                                  │
                                                                  │ Scraping & Coleta
                                                                  ▼
                                  TRÁFEGO DE SAÍDA (EGRESS ANTI-BOT)
                               ┌───────────────────────────────────────────────────────┐
                               │              SCRAPER EGRESS GATEWAY                   │
                               │          (Forward Proxy Cluster / Squid)              │
                               │                                                       │
                               │  • TLS Fingerprint / JA3 Masquerade                   │
                               │  • User-Agent & Header Rotation                       │
                               │  • Smart Router:                                      │
                               │      - Direto (B3, CVM, BCB, ETFsBrasil)              │
                               │      - Datacenter Rotativo (StatusInvest, FundsExp)   │
                               │      - Sticky Session (Investidor10, Fundamentus)     │
                               │      - Residential Pools (MaisRetorno, ADVFN)         │
                               └──────────────────────────┬────────────────────────────┘
                                                          │
                   ┌──────────────────────────────┬───────┴──────────────────────┬──────────────────────────────┐
                   ▼                              ▼                              ▼                              ▼
          [Órgãos Oficiais]               [Sites Leves]                  [Sites Médios]                 [Sites WAF Estrito]
          B3, CVM, BCB, ANBIMA          FIIs.com.br, ETFsBrasil       StatusInvest, Brick360         MaisRetorno, ADVFN,
                                        AnáliseDeAções, Fundamentei   FundsExplorer, ClubeFII        Investidor10, Fundamentus
```

---

## 5. Requisitos Técnicos do Gateway Ingress & Egress

### 5.1 Ingress API Gateway (Para Clientes Externos)
1. **Roteamento Inteligente:**
   - `/api/v1/*` encaminhado para os containers do `fin-api`.
   - `/billing/webhooks/{provider}` encaminhado para o handler de pagamentos com preservação do payload binário bruto (necessário para validação da assinatura HMAC criptográfica).
   - `/health` e `/metrics` protegidos contra acesso público externo (restritos à VPC interna ou redes de monitoramento).
2. **Rate Limiting por Token Bucket:**
   - Tier Anônimo: 30 requisições/minuto por IP.
   - Tier Free Autenticado: 120 requisições/minuto.
   - Tier Pro / Enterprise: 600 a 3000 requisições/minuto.
3. **Segurança de Borda:**
   - TLS 1.3 obrigatório com cipher suites seguras.
   - Headers: `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Content-Security-Policy`.

### 5.2 Scraper Egress Gateway (Para Coleta Externa)
1. **Roteamento por Domínio:**
   O proxy intercepta requisições de saída dos coletores e aplica o perfil adequado:
   - **Perfil 1 (Direct VPC NAT):** Destinado a `dados.cvm.gov.br`, `api.bcb.gov.br`, `b3.com.br`, `etfsbrasil.com.br`. Latência mínima (<30ms), sem custo de proxy.
   - **Perfil 2 (Datacenter Rotating):** Destinado a `statusinvest.com.br`, `fundamentei.com`, `brick360.com.br`, `fundsexplorer.com.br`. Rotação de IP por requisição ou a cada 50 requests.
   - **Perfil 3 (Sticky Session ISP):** Destinado a `investidor10.com.br`, `fundamentus.com.br`, `clubefii.com.br`. Mantém o mesmo IP durante o ciclo de sessão para preservar cookies e tokens de CSRF.
   - **Perfil 4 (Residential Rotating):** Destinado a `maisretorno.com` e `br.advfn.com`. Alta rotatividade de IPs residenciais limpos para evitar bloqueios CloudFront/Incapsula.
2. **Circuit Breakers Distribuídos (no Redis):**
   - Estado: `CLOSED` (Normal), `OPEN` (Falha ativa), `HALF-OPEN` (Testando recuperação).
   - Regra: 5 erros consecutivos (HTTP 403, 429 ou 5xx) acionam `OPEN` por 15 minutos para aquele domínio.
   - Alertas imediatos enviados para o Prometheus e Alertmanager.

---

## 6. Requisitos de Observabilidade para os Scrapers

O Prometheus e o Grafana devem monitorar especificamente:
1. `fin_scraper_requests_total{source, status_code}`: Volume de requisições por site e status HTTP.
2. `fin_scraper_duration_seconds{source}`: Latência de scraping por plataforma (p50, p95, p99).
3. `fin_scraper_circuit_breaker_state{source}`: Estado atual do circuito (0=Closed, 1=Half-Open, 2=Open).
4. `fin_scraper_rate_limit_hits_total{source}`: Ocorrências de HTTP 429 por domínio.
5. `fin_scraper_payload_bytes{source}`: Volume de dados brutos pousados no PostgreSQL `raw.payload`.
