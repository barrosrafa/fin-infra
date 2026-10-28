#!/usr/bin/env python3
"""Script de verificação de conectividade e integridade do deploy em nuvem distribuída."""

import sys
import time
import argparse
import urllib.request
import urllib.error
import json


def check_url(url: str, label: str, timeout: int = 10) -> bool:
    print(f"\n🔍 Verificando {label} ({url})...")
    start = time.time()
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Fin-Cloud-Deploy-Verifier/1.0", "Accept": "*/*"}
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            latency = (time.time() - start) * 1000
            status = response.status
            content = response.read(2048).decode("utf-8", errors="ignore")
            
            if status in [200, 204]:
                print(f"  ✅ [SUCESSO] Status {status} ({latency:.1f}ms)")
                try:
                    data = json.loads(content)
                    print(f"  📄 Resposta: {json.dumps(data, indent=2)}")
                except Exception:
                    preview = content.strip().split("\n")[0][:120]
                    print(f"  📄 Conteúdo: {preview}...")
                return True
            else:
                print(f"  ⚠️ [AVISO] Status inesperado {status}")
                return False
    except urllib.error.HTTPError as e:
        latency = (time.time() - start) * 1000
        print(f"  ❌ [FALHA HTTP {e.code}] ({latency:.1f}ms): {e.reason}")
        return False
    except Exception as e:
        latency = (time.time() - start) * 1000
        print(f"  ❌ [ERRO DE CONEXÃO] ({latency:.1f}ms): {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Verificador de Deploy em Nuvem para fin-api e fin-web")
    parser.add_argument("--api-url", default="http://localhost:8000", help="URL base da API (ex: https://fin-api.koyeb.app)")
    parser.add_argument("--web-url", default="http://localhost:3000", help="URL base do Web (ex: https://fin-web.vercel.app)")
    args = parser.parse_args()

    api_base = args.api_url.rstrip("/")
    web_base = args.web_url.rstrip("/")

    print("=================================================================")
    print(" 🚀 Teste de Integridade da Arquitetura Distribuída fin")
    print("=================================================================")

    results = []
    # 1. API Health Check
    results.append(check_url(f"{api_base}/health", "API Health Endpoint"))

    # 2. API Public Market Route
    results.append(check_url(f"{api_base}/api/v1/market/quote/PETR4", "API Market Quote (PETR4)"))

    # 3. Web Home Page
    results.append(check_url(f"{web_base}", "Frontend Web Home"))

    # 4. Web Ações Page
    results.append(check_url(f"{web_base}/acoes", "Frontend Web /acoes"))

    print("\n-----------------------------------------------------------------")
    passed = sum(1 for r in results if r)
    total = len(results)
    print(f"Resultado Final: {passed}/{total} verificações aprovadas.")
    if passed == total:
        print("🎉 Todos os serviços remotos estão operando com sucesso!")
        return 0
    else:
        print("⚠️ Alguns serviços reportaram avisos ou falhas. Verifique os logs acima.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
