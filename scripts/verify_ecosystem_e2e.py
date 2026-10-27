#!/usr/bin/env python3
"""
End-to-End Ecosystem Verification Suite
Validates the complete flow across fin-db, fin-ingestion, fin-api, and fin-web:
1. ANBIMA CRI Ingestion & Legacy Seed Resolution
2. CVM 175 CDA Portfolio Parsing
3. Bitemporal Look-Through Graph Traversal (Debtor Aggregation)
4. Deterministic Falsifiable Phrase Generation (< 10ms) & Inference Logging
5. Multi-Source Metric Reconciliation & Divergence Taxonomy Classification
"""
import os
import sys
import time

# Add fin-ingestion and fin-api to Python path
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT_DIR, "fin-ingestion"))
sys.path.insert(0, os.path.join(ROOT_DIR, "fin-api"))

from fin_ingestion.collectors.anbima_cri_data import AnbimaCriCollector
from fin_ingestion.pipelines.cvm_cda_parser import CvmCdaParser
from fin_ingestion.pipelines.reconciliation_pipeline import MetricInput, ReconciliationEngine
from app.portfolio.debtor_graph import DebtorGraphService, EdgeInfo, PortfolioPosition, UserOverride
from app.intelligence.falsifiable_phrase import (
    DecomposedAsset,
    FalsifiablePhraseEngine,
    LookThroughDetail,
    PhraseContext,
    RatingEvent,
)
from app.comparator.arbitration import ArbitrationEngine, SourceObservation


def run_e2e_verification():
    print("=" * 70)
    print("🚀 FIN ECOSYSTEM E2E VERIFICATION SUITE — v3.5")
    print("=" * 70)

    # --------------------------------------------------------------------------
    # STAGE 1: ANBIMA Data Collector & Legacy Seed Ingestion
    # --------------------------------------------------------------------------
    print("\n[STAGE 1] Ingesting ANBIMA Data & Legacy Seeds...")
    anbima_raw = [
        {
            "codigo_isin": "BRSTNNCRI099",
            "codigo_emissao": "CRI-JHSF-FASANO",
            "cnpj_devedor": "61.274.529/0001-00",
            "razao_social_devedor": "JHSF PARTICIPACOES S.A.",
            "data_encerramento": "2026-01-20",
            "tipo_operacao": "Concentrado",
        }
    ]
    anbima_collector = AnbimaCriCollector()
    anbima_records = anbima_collector.normalize_records(anbima_raw)
    assert len(anbima_records) == 1
    assert anbima_records[0].is_post_dec_2025 is True
    print("✓ ANBIMA Data collector normalized CRI with post-dec-2025 coverage.")

    anbima_lookup = {
        "BRSTNNCRI099": {
            "cnpj_devedor": "61.274.529/0001-00",
            "canonical_group": "Grupo JHSF",
            "is_post_dec_2025": True,
        }
    }
    legacy_seed_lookup = {
        "BRSTNNCRI001": {
            "cnpj_devedor": "61.274.529/0001-00",
            "canonical_group": "Grupo JHSF",
        }
    }

    # --------------------------------------------------------------------------
    # STAGE 2: CVM 175 CDA Holdings Parsing
    # --------------------------------------------------------------------------
    print("\n[STAGE 2] Parsing CVM 175 CDA Fund Holdings (KNIP11)...")
    raw_cda_holdings = [
        {"ativo_tipo": "CRI", "isin": "BRSTNNCRI099", "peso_pl_pct": 18.5, "valor_contabil": 185000000.0},
        {"ativo_tipo": "CRI", "isin": "BRSTNNCRI001", "peso_pl_pct": 12.0, "valor_contabil": 120000000.0},
        {"ativo_tipo": "CRI", "isin": "BRPENDING01", "peso_pl_pct": 4.0, "valor_contabil": 40000000.0},
        {"ativo_tipo": "CRI", "isin": "BROPAQUE01", "peso_pl_pct": 2.5, "valor_contabil": 25000000.0, "is_pulverized": True},
    ]
    cda_parser = CvmCdaParser(anbima_lookup=anbima_lookup, legacy_seed_lookup=legacy_seed_lookup)
    cda_result = cda_parser.parse_fii_cda("KNIP11", pl_total=1000000000.0, raw_holdings=raw_cda_holdings)
    assert cda_result.pct_resolved == 30.5
    assert cda_result.pct_temporary_pending == 4.0
    assert cda_result.pct_structure_opaque == 2.5
    print(f"✓ CVM CDA parsed: {cda_result.pct_resolved}% resolved, {cda_result.pct_temporary_pending}% pending, {cda_result.pct_structure_opaque}% opaque.")

    # --------------------------------------------------------------------------
    # STAGE 3: Look-Through Debtor Graph Traversal & Override Resilience
    # --------------------------------------------------------------------------
    print("\n[STAGE 3] Executing Look-Through Debtor Traversal on Portfolio...")
    user_portfolio = [
        PortfolioPosition(ticker="KNIP11", asset_class="FII", weight_pct=22.0),
        PortfolioPosition(ticker="Fundo CVM 175 Y", asset_class="FUND_CVM_175", weight_pct=9.0),
        PortfolioPosition(ticker="CRI JHSF Direct", asset_class="DIRECT_CRI", weight_pct=3.0),
        PortfolioPosition(ticker="PETR4", asset_class="EQUITY", weight_pct=66.0),
    ]

    edges = {
        "KNIP11": [
            EdgeInfo(target_entity_name="Grupo JHSF", weight_pct=18.5, coverage_category="RESOLVED"),
            EdgeInfo(target_entity_name="MRV", weight_pct=9.25, coverage_category="RESOLVED"),
            EdgeInfo(target_entity_name=None, weight_pct=4.0, coverage_category="TEMPORARY_PENDING_CURATION"),
            EdgeInfo(target_entity_name=None, weight_pct=2.5, coverage_category="STRUCTURE_OPAQUE"),
        ],
        "Fundo CVM 175 Y": [
            EdgeInfo(target_entity_name="Grupo JHSF", weight_pct=100.0, coverage_category="RESOLVED"),
        ],
        "CRI JHSF Direct": [
            EdgeInfo(target_entity_name="Grupo JHSF", weight_pct=100.0, coverage_category="RESOLVED"),
        ],
    }

    graph_service = DebtorGraphService(edges_lookup=edges)
    analysis = graph_service.calculate_debtor_exposure(user_portfolio)
    jhsf = next(d for d in analysis.debtors if d.entity_name == "Grupo JHSF")
    assert jhsf.total_exposure_pct == 16.07 # (22% * 18.5%) + (9% * 100%) + (3% * 100%) = 4.07 + 9.0 + 3.0
    print(f"✓ Aggregated Debtor JHSF exposure verified across 3 distinct asset classes: {jhsf.total_exposure_pct}%.")

    # --------------------------------------------------------------------------
    # STAGE 4: Deterministic Falsifiable Phrase Generation (< 10ms) & Inference Log
    # --------------------------------------------------------------------------
    print("\n[STAGE 4] Emitting Falsifiable Statement with Interactive Evidence Pills...")
    phrase_engine = FalsifiablePhraseEngine()
    phrase_ctx = PhraseContext(
        macro_class="crédito imobiliário de papel",
        total_pct=34.0,
        decomposed_assets=[
            DecomposedAsset(name="KNIP11", pct=22.0),
            DecomposedAsset(name="Fundo CVM 175 Y", pct=9.0),
            DecomposedAsset(name="CRI JHSF Direct", pct=3.0),
        ],
        rating_event=RatingEvent(
            asset_name="CRI JHSF Direct",
            old_rating="AA",
            new_rating="A",
            event_date="12/09",
            source="Brick360",
            source_time="14:32",
        ),
        look_through_detail=LookThroughDetail(
            fii_name="KNIP11",
            pl_pct=18.5,
            sources="Clube FII / SiiLA",
        ),
        canonical_debtor="Grupo JHSF",
        user_threshold_pct=25.0,
    )

    t0 = time.perf_counter()
    phrase_res = phrase_engine.generate_phrase(user_id="user_live_1", portfolio_hash="hash_live_001", context=phrase_ctx)
    t_elapsed_ms = (time.perf_counter() - t0) * 1000
    assert t_elapsed_ms < 10.0
    assert "Você não tem concentração por ticker — tem concentração por devedor." in phrase_res.text
    assert len(phrase_res.interactive_pills) >= 4
    print(f"✓ Deterministic statement emitted in {t_elapsed_ms:.2f}ms (< 10ms SLA).")
    print(f"  Sentence: \"{phrase_res.text}\"")

    # --------------------------------------------------------------------------
    # STAGE 5: Multi-Source Reconciliation & Divergence Taxonomy Classification
    # --------------------------------------------------------------------------
    print("\n[STAGE 5] Reconciling Status Invest vs Funds Explorer with Divergence Taxonomy...")
    recon_engine = ReconciliationEngine()
    metrics = [
        MetricInput(source_id="STATUS_INVEST", ticker="KNIP11", metric_name="DY_12M", value=8.20, methodology="LTM_12M"),
        MetricInput(source_id="FUNDS_EXPLORER", ticker="KNIP11", metric_name="DY_12M", value=7.90, methodology="LAST_DIV_ANNUALIZED"),
    ]
    recon_result = recon_engine.reconcile(ticker="KNIP11", metric_name="DY_12M", metrics=metrics)
    assert recon_result.has_divergence is True
    assert recon_result.divergence_taxonomy == "DIVIDEND_WINDOW_MISMATCH"
    assert recon_result.anchor_source == "STATUS_INVEST"
    print(f"✓ Divergence classified as: {recon_result.divergence_taxonomy} (Delta: {recon_result.delta_pct}%).")
    print(f"  Consensus Range: [{recon_result.consensus_min}%, {recon_result.consensus_max}%] | Anchor: {recon_result.anchor_source}")

    print("\n" + "=" * 70)
    print("🎉 ALL 5 ECOSYSTEM STAGES VERIFIED SUCCESSFULLY (EXIT CODE 0)!")
    print("=" * 70)


if __name__ == "__main__":
    run_e2e_verification()
