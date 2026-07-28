"""
batch_control.py
----------------
ETL batch lifecycle against audit.etl_batch_control. One row per table load:

    start_batch  -> status 'running'
    complete_batch -> status 'succeeded' (+ row counts + new watermark)
    fail_batch   -> status 'failed' (+ error message)

The numeric ``batch_key`` returned by start_batch is stamped onto every Bronze
row as ``bronze_batch_id`` (lineage back to the batch that produced the row).
The watermark window is stored on the same row (watermark_value_start/end), so
the audit schema needs no separate watermark table.
"""

from __future__ import annotations

import threading
from datetime import datetime
from typing import Any

from sqlalchemy import text

from ingestion.utils.database import get_dw_engine
from ingestion.utils.logger import get_logger

logger = get_logger(__name__)

# audit.etl_batch_control.batch_id is VARCHAR(50) (see sql/audit DDL).
_BATCH_ID_MAX_LEN = 50

# batch_id uniqueness must not depend on the clock ticking between calls: the
# DAG opens four gold batches in a tight loop, and two calls landing in the same
# microsecond would collide against uq_etl_batch_control_batch_id and fail the
# task. This counter makes the value strictly increasing within a process even
# if the clock has not advanced; across processes the wall clock separates them.
_epoch_lock = threading.Lock()
_last_epoch_micros = 0


def _next_epoch_micros() -> int:
    """Return a strictly increasing microsecond timestamp (per process)."""
    global _last_epoch_micros
    with _epoch_lock:
        now = int(datetime.now().timestamp() * 1_000_000)
        if now <= _last_epoch_micros:
            now = _last_epoch_micros + 1
        _last_epoch_micros = now
        return now


def build_batch_id(target_table: str) -> str:
    """Build the external batch identifier: ``<target_table>:<epoch_micros>``.

    Guaranteed to fit ``audit.etl_batch_control.batch_id`` (VARCHAR(50)) for any
    target name. The epoch suffix is what makes the id UNIQUE, so when the name
    is long the readable PREFIX is trimmed and the suffix never is — trimming
    the suffix could collide against uq_etl_batch_control_batch_id. Nothing is
    lost: the full name is stored separately in target_table VARCHAR(100), and
    pipeline_name is recorded in initiated_by.

    Kept as a pure function (no DB) so the width guarantee is unit-testable —
    this overflowed twice in production-shaped runs before it was enforced here
    (see docs/fix/fix_log.md, FIX-002).
    """
    suffix = f":{_next_epoch_micros()}"
    return f"{target_table[: _BATCH_ID_MAX_LEN - len(suffix)]}{suffix}"


def start_batch(
    pipeline_name: str,
    source_system: str,
    target_table: str,
    load_type: str,
    watermark_column: str | None = None,
    watermark_value_start: str | None = None,
    engine: Any = None,
) -> tuple[int, str]:
    """Insert a 'running' batch row into audit.etl_batch_control.

    Returns
    -------
    (batch_key, batch_id)
        batch_key — numeric surrogate stamped onto Bronze rows as bronze_batch_id.
        batch_id  — external unique identifier (pipeline:table:epoch_ms).
    """
    engine = engine or get_dw_engine()
    batch_id = build_batch_id(target_table)
    sql = text(
        """
        INSERT INTO audit.etl_batch_control
            (batch_id, source_system, target_table, load_type, watermark_column,
             watermark_value_start, batch_status, batch_start_timestamp, initiated_by)
        VALUES
            (:batch_id, :source_system, :target_table, :load_type, :watermark_column,
             :watermark_value_start, 'running', clock_timestamp(), :initiated_by)
        RETURNING batch_key
        """
    )
    with engine.begin() as conn:
        batch_key = conn.execute(
            sql,
            {
                "batch_id": batch_id,
                "source_system": source_system,
                "target_table": target_table,
                "load_type": load_type,
                "watermark_column": watermark_column,
                "watermark_value_start": watermark_value_start,
                "initiated_by": pipeline_name,
            },
        ).scalar()
    logger.info(
        "Batch started | key=%s id=%s table=%s", batch_key, batch_id, target_table
    )
    return int(batch_key), batch_id


def complete_batch(
    batch_key: int,
    rows_extracted: int,
    rows_inserted: int,
    watermark_value_end: str | None = None,
    engine: Any = None,
) -> None:
    """Mark a batch succeeded with row counts and the new high-water mark."""
    engine = engine or get_dw_engine()
    sql = text(
        """
        UPDATE audit.etl_batch_control
        SET batch_status = 'succeeded',
            batch_end_timestamp = clock_timestamp(),
            rows_extracted = :rows_extracted,
            rows_inserted = :rows_inserted,
            watermark_value_end = COALESCE(:watermark_value_end, watermark_value_end)
        WHERE batch_key = :batch_key
        """
    )
    with engine.begin() as conn:
        conn.execute(
            sql,
            {
                "batch_key": batch_key,
                "rows_extracted": rows_extracted,
                "rows_inserted": rows_inserted,
                "watermark_value_end": watermark_value_end,
            },
        )
    logger.info(
        "Batch completed | key=%s extracted=%s inserted=%s",
        batch_key,
        rows_extracted,
        rows_inserted,
    )


def fail_batch(batch_key: int, error_message: str, engine: Any = None) -> None:
    """Mark a batch failed with the truncated error message."""
    engine = engine or get_dw_engine()
    sql = text(
        """
        UPDATE audit.etl_batch_control
        SET batch_status = 'failed',
            batch_end_timestamp = clock_timestamp(),
            error_message = :error_message
        WHERE batch_key = :batch_key
        """
    )
    with engine.begin() as conn:
        conn.execute(
            sql, {"batch_key": batch_key, "error_message": error_message[:2000]}
        )
    logger.warning("Batch failed | key=%s error=%s", batch_key, error_message[:200])
