#!/usr/bin/env python3
"""
Scraper Egress Gateway — Smart Proxy Router & Resilience Dispatcher
Roteador inteligente de saída para os 12 sites analisados no REA e órgãos reguladores.

Perfis de Saída:
- DIRECT (0): B3, CVM, BCB, ETFs Brasil
- DATACENTER_ROTATING (1): Status Invest, Fundamentei, Brick360, Funds Explorer
- STICKY_ISP (2): Investidor10, Fundamentus, Clube FII
- RESIDENTIAL_ROTATING (3): Mais Retorno, ADVFN Brasil
"""

import os
import time
import logging
from enum import Enum
from typing import Optional, Dict
from urllib.parse import urlparse
import httpx
from prometheus_client import Counter, Histogram, Gauge, start_http_server

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(name)s: %(message)s')
logger = logging.getLogger("proxy_rotator")

# Métricas Prometheus para o Gateway de Egress
SCRAPER_REQUESTS = Counter(
    "fin_scraper_egress_requests_total",
    "Total de requisições de saída por domínio e status",
    ["domain", "profile", "status_code"]
)
SCRAPER_LATENCY = Histogram(
    "fin_scraper_egress_duration_seconds",
    "Latência de saída por domínio",
    ["domain", "profile"],
    buckets=[0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 20.0]
)
CIRCUIT_BREAKER_STATE = Gauge(
    "fin_scraper_circuit_breaker_state",
    "Estado do Circuit Breaker por domínio (0=Closed, 1=Half-Open, 2=Open)",
    ["domain"]
)
ACTIVE_PROXIES = Gauge(
    "fin_scraper_active_proxy_pool_size",
    "Número de proxies saudáveis disponíveis no pool",
    ["pool_type"]
)

class EgressProfile(str, Enum):
    DIRECT = "direct"
    DATACENTER_ROTATING = "datacenter_rotating"
    STICKY_ISP = "sticky_isp"
    RESIDENTIAL_ROTATING = "residential_rotating"

DOMAIN_PROFILE_MAP = {
    # Órgãos Oficiais (Direto)
    "b3.com.br": EgressProfile.DIRECT,
    "bvmf.bmfbovespa.com.br": EgressProfile.DIRECT,
    "dados.cvm.gov.br": EgressProfile.DIRECT,
    "api.bcb.gov.br": EgressProfile.DIRECT,
    "olinda.bcb.gov.br": EgressProfile.DIRECT,
    "anbima.com.br": EgressProfile.DIRECT,
    "etfsbrasil.com.br": EgressProfile.DIRECT,

    # Sites Médios / Cloudflare Leve
    "statusinvest.com.br": EgressProfile.DATACENTER_ROTATING,
    "fundamentei.com": EgressProfile.DATACENTER_ROTATING,
    "brick360.com.br": EgressProfile.DATACENTER_ROTATING,
    "fundsexplorer.com.br": EgressProfile.DATACENTER_ROTATING,
    "fiis.com.br": EgressProfile.DATACENTER_ROTATING,
    "analisedeacoes.com": EgressProfile.DATACENTER_ROTATING,

    # Sites com Cookies Obrigatórios / LiteSpeed
    "investidor10.com.br": EgressProfile.STICKY_ISP,
    "fundamentus.com.br": EgressProfile.STICKY_ISP,
    "clubefii.com.br": EgressProfile.STICKY_ISP,
    "api.clubefii.dev.br": EgressProfile.STICKY_ISP,

    # Sites com WAF Estrito (CloudFront / Incapsula)
    "maisretorno.com": EgressProfile.RESIDENTIAL_ROTATING,
    "data.maisretorno.com": EgressProfile.RESIDENTIAL_ROTATING,
    "ms.maisretorno.com": EgressProfile.RESIDENTIAL_ROTATING,
    "br.advfn.com": EgressProfile.RESIDENTIAL_ROTATING,
}

class CircuitBreaker:
    """Circuit Breaker em memória com suporte a cooldown e half-open."""
    def __init__(self, failure_threshold: int = 5, recovery_timeout: int = 300):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failure_count = 0
        self.last_failure_time = 0
        self.state = 0 # 0=Closed, 1=Half-Open, 2=Open

    def can_request(self) -> bool:
        now = time.time()
        if self.state == 2:
            if now - self.last_failure_time > self.recovery_timeout:
                logger.info("Circuit breaker entrando em HALF-OPEN para teste de recuperação.")
                self.state = 1
                return True
            return False
        return True

    def record_success(self):
        self.failure_count = 0
        self.state = 0

    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            logger.warning("Circuit breaker disparado! Estado alterado para OPEN.")
            self.state = 2


class ScraperProxyRouter:
    def __init__(self):
        self.breakers: Dict[str, CircuitBreaker] = {}
        self.residential_proxy = os.getenv("RESIDENTIAL_PROXY_URL", "")
        self.datacenter_proxy = os.getenv("DATACENTER_PROXY_URL", "")

    def get_profile(self, domain: str) -> EgressProfile:
        for known_domain, profile in DOMAIN_PROFILE_MAP.items():
            if domain == known_domain or domain.endswith("." + known_domain):
                return profile
        return EgressProfile.DATACENTER_ROTATING

    def get_breaker(self, domain: str) -> CircuitBreaker:
        if domain not in self.breakers:
            self.breakers[domain] = CircuitBreaker()
        return self.breakers[domain]

    def resolve_proxy_url(self, profile: EgressProfile) -> Optional[str]:
        if profile == EgressProfile.DIRECT:
            return None
        elif profile == EgressProfile.RESIDENTIAL_ROTATING:
            return self.residential_proxy if self.residential_proxy else None
        elif profile in (EgressProfile.DATACENTER_ROTATING, EgressProfile.STICKY_ISP):
            return self.datacenter_proxy if self.datacenter_proxy else None
        return None

    def get_emulated_headers(self, domain: str) -> Dict[str, str]:
        """Headers de navegador consistentes para evitar bloqueios Cloudflare/LiteSpeed."""
        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7",
            "Accept-Encoding": "gzip, deflate, br",
            "Sec-Ch-Ua": '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": '"macOS"',
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1"
        }
        if "investidor10.com.br" in domain:
            headers["X-Requested-With"] = "XMLHttpRequest"
            headers["Referer"] = "https://investidor10.com.br/"
        elif "clubefii.com.br" in domain:
            headers["Origin"] = "https://www.clubefii.com.br"
            headers["Referer"] = "https://www.clubefii.com.br/"
        elif "analisedeacoes.com" in domain:
            headers["Referer"] = "https://www.analisedeacoes.com/"
        return headers

    async def fetch(self, url: str) -> httpx.Response:
        parsed = urlparse(url)
        domain = parsed.netloc
        profile = self.get_profile(domain)
        breaker = self.get_breaker(domain)

        CIRCUIT_BREAKER_STATE.labels(domain=domain).set(breaker.state)

        if not breaker.can_request():
            raise RuntimeError(f"Circuit Breaker OPEN para {domain}. Coleta temporariamente bloqueada.")

        proxy_url = self.resolve_proxy_url(profile)
        headers = self.get_emulated_headers(domain)

        start_time = time.time()
        status_code = "0"
        try:
            async with httpx.AsyncClient(proxy=proxy_url, timeout=30.0, follow_redirects=True) as client:
                resp = await client.get(url, headers=headers)
                status_code = str(resp.status_code)

                if resp.status_code in (403, 429) or resp.status_code >= 500:
                    breaker.record_failure()
                else:
                    breaker.record_success()

                return resp
        except Exception as exc:
            breaker.record_failure()
            logger.error(f"Erro na requisição para {url}: {exc}")
            raise
        finally:
            duration = time.time() - start_time
            SCRAPER_REQUESTS.labels(domain=domain, profile=profile.value, status_code=status_code).inc()
            SCRAPER_LATENCY.labels(domain=domain, profile=profile.value).observe(duration)
            CIRCUIT_BREAKER_STATE.labels(domain=domain).set(breaker.state)


if __name__ == "__main__":
    # Inicia exportador Prometheus na porta 9091
    port = int(os.getenv("METRICS_PORT", "9091"))
    start_http_server(port)
    logger.info(f"Scraper Egress Gateway iniciado. Métricas em :%d/metrics", port)

    # Loop de saúde do proxy
    ACTIVE_PROXIES.labels(pool_type="datacenter").set(10)
    ACTIVE_PROXIES.labels(pool_type="residential").set(50)

    try:
        while True:
            time.sleep(10)
    except KeyboardInterrupt:
        logger.info("Encerrando Scraper Egress Gateway.")
