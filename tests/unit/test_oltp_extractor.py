"""Unit tests for OLTPExtractor query construction.

These exercise the pure SQL-builder helpers only — no database connection is
opened, so they run anywhere without OLTP/DW credentials.
"""

from __future__ import annotations

from datetime import datetime

import pytest

from ingestion.extract.oltp_extractor import OLTPExtractor


def _extractor() -> OLTPExtractor:
    return OLTPExtractor(source_name="oltp_printtime", pipeline_name="test_pipeline")


def test_full_load_query_selects_all_rows() -> None:
    sql, params = _extractor()._build_full_load_query("customer")
    assert str(sql) == "SELECT * FROM customer"
    assert params == {}


def test_incremental_query_without_watermark_is_full_load() -> None:
    sql, params = _extractor()._build_incremental_query("invoice", "updated_at", None)
    assert str(sql) == "SELECT * FROM invoice"
    assert params == {}


def test_incremental_query_binds_watermark_value() -> None:
    # The watermark VALUE is a bound parameter, never interpolated (MED-1), and
    # is shifted back by the lookback window to catch in-flight commits (MED-2).
    sql, params = _extractor()._build_incremental_query(
        "invoice", "updated_at", "2026-01-01 00:00:00"
    )
    assert str(sql) == "SELECT * FROM invoice WHERE updated_at > :watermark"
    assert params == {"watermark": datetime(2025, 12, 31, 23, 0, 0)}  # 1h lookback
    # the literal value must NOT reach the SQL text
    assert "2026-01-01" not in str(sql)


def test_watermark_lookback_shifts_value_back() -> None:
    # MED-2: the extraction floor is (watermark - WATERMARK_LOOKBACK).
    _, params = _extractor()._build_incremental_query(
        "invoice", "updated_at", "2026-03-10 12:30:00"
    )
    assert params["watermark"] == datetime(2026, 3, 10, 11, 30, 0)


def test_non_timestamp_watermark_passes_through() -> None:
    # A watermark that isn't a timestamp can't be shifted; it is left unchanged
    # so the strict comparison still holds.
    _, params = _extractor()._build_incremental_query("invoice", "seq_id", "not-a-date")
    assert params["watermark"] == "not-a-date"


@pytest.mark.parametrize(
    "bad_name",
    ["customer; drop table x", "a b", "x'--", "updated_at) OR 1=1", ""],
)
def test_unsafe_table_identifiers_are_rejected(bad_name: str) -> None:
    with pytest.raises(ValueError):
        _extractor()._build_full_load_query(bad_name)


def test_unsafe_watermark_column_is_rejected() -> None:
    with pytest.raises(ValueError):
        _extractor()._build_incremental_query("invoice", "updated_at) OR 1=1", "x")
