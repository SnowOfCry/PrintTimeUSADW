"""Unit tests for OLTPExtractor query construction.

These exercise the pure SQL-builder helpers only — no database connection is
opened, so they run anywhere without OLTP/DW credentials.
"""

from __future__ import annotations

from ingestion.extract.oltp_extractor import OLTPExtractor


def _extractor() -> OLTPExtractor:
    return OLTPExtractor(source_name="oltp_printtime", pipeline_name="test_pipeline")


def test_full_load_query_selects_all_rows() -> None:
    sql = _extractor()._build_full_load_query("customer")
    assert sql == "SELECT * FROM customer"


def test_incremental_query_without_watermark_is_full_load() -> None:
    sql = _extractor()._build_incremental_query("invoice", "updated_at", None)
    assert sql == "SELECT * FROM invoice"


def test_incremental_query_filters_on_watermark() -> None:
    sql = _extractor()._build_incremental_query(
        "invoice", "updated_at", "2026-01-01 00:00:00"
    )
    assert "WHERE updated_at > '2026-01-01 00:00:00'" in sql
    assert sql.startswith("SELECT * FROM invoice")
