"""
watermark.py
------------
Reads the incremental high-water mark from audit.etl_batch_control.

Watermarks let incremental loads pick up only new/changed source rows since the
last successful batch. In the audit-schema design the watermark is stored on the
batch row itself (audit.etl_batch_control.watermark_value_end) rather than a
separate watermark table; it is written by batch_control.complete_batch.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import text

from ingestion.utils.config_loader import load_config
from ingestion.utils.database import get_dw_engine
from ingestion.utils.logger import get_logger

logger = get_logger(__name__)


def get_watermark(
    pipeline_name: str,
    source_name: str,
    source_table: str,
) -> str | datetime | None:
    """
    Return the last successful high-water mark for a source table.

    Looks up the most recent succeeded batch for the table's Bronze target in
    audit.etl_batch_control and returns its watermark_value_end. Returns None if
    the table has never loaded successfully (caller then performs a full load).

    Parameters
    ----------
    pipeline_name : str
        Owning pipeline name (unused in the lookup; kept for interface stability).
    source_name : str
        Source system name (unused in the lookup; kept for interface stability).
    source_table : str
        Source table name (e.g. 'customer'); resolved to its Bronze target via
        ingestion_config.yml.
    """
    config = load_config()
    match = next(
        (t for t in config.get("tables", []) if t.get("name") == source_table),
        None,
    )
    if match is None or not match.get("bronze_table"):
        logger.warning(
            "No bronze_table mapping for source '%s'; no watermark (full load).",
            source_table,
        )
        return None
    target_table = match["bronze_table"]

    sql = text(
        """
        SELECT watermark_value_end
        FROM audit.etl_batch_control
        WHERE target_table = :target_table
          AND batch_status = 'succeeded'
          AND watermark_value_end IS NOT NULL
        ORDER BY batch_end_timestamp DESC
        LIMIT 1
        """
    )
    engine = get_dw_engine()
    with engine.connect() as conn:
        row = conn.execute(sql, {"target_table": target_table}).fetchone()

    value = row[0] if row else None
    logger.info(
        "Watermark | source=%s target=%s value=%s", source_table, target_table, value
    )
    return value
