"""
watermark.py
------------
Utilities for reading and updating high-water marks in control.elt_watermark.

Watermarks allow incremental ELT loads to pick up only new or changed rows
since the last successful pipeline run.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)


def get_watermark(
    pipeline_name: str,
    source_name: str,
    source_table: str,
) -> str | datetime | None:
    """
    Retrieve the last successful watermark value for a source table.

    Returns None if no previous run exists (triggers a full load).

    Parameters
    ----------
    pipeline_name : str
        Owning pipeline name (matches elt_watermark.pipeline_name).
    source_name : str
        Source system name (matches elt_watermark.source_name).
    source_table : str
        Source table name (matches elt_watermark.source_table).

    Returns
    -------
    str | datetime | None
        Last watermark value, or None if the table has never been loaded.
    """
    logger.debug(
        "Reading watermark | pipeline=%s source=%s table=%s",
        pipeline_name,
        source_name,
        source_table,
    )

    # TODO: Replace with real query once DW connection is wired up.
    # from ingestion.utils.database import get_dw_psycopg2_conn
    # with get_dw_psycopg2_conn() as conn:
    #     with conn.cursor() as cur:
    #         cur.execute(
    #             """
    #             SELECT last_watermark_value
    #             FROM   control.elt_watermark
    #             WHERE  pipeline_name = %s
    #               AND  source_name   = %s
    #               AND  source_table  = %s
    #               AND  is_active     = TRUE
    #             """,
    #             (pipeline_name, source_name, source_table),
    #         )
    #         row = cur.fetchone()
    #         return row["last_watermark_value"] if row else None

    logger.warning("PLACEHOLDER: get_watermark returning None — wire in real DB query.")
    return None


def update_watermark(
    pipeline_name: str,
    source_name: str,
    source_table: str,
    target_schema: str,
    target_table: str,
    watermark_column: str,
    new_watermark_value: Any,
    batch_id: int,
) -> None:
    """
    Upsert the watermark for a source table after a successful load.

    Parameters
    ----------
    pipeline_name : str
    source_name : str
    source_table : str
    target_schema : str
    target_table : str
    watermark_column : str
        Column name used as the watermark (e.g. 'updated_at').
    new_watermark_value : Any
        The highest value of watermark_column seen in this batch.
    batch_id : int
        The batch_id from control.elt_batch_log for this run.
    """
    logger.info(
        "Updating watermark | pipeline=%s source=%s table=%s value=%s",
        pipeline_name,
        source_name,
        source_table,
        new_watermark_value,
    )

    # TODO: Replace with real UPSERT once DW connection is wired up.
    # from ingestion.utils.database import get_dw_psycopg2_conn
    # with get_dw_psycopg2_conn() as conn:
    #     with conn.cursor() as cur:
    #         cur.execute(
    #             """
    #             INSERT INTO control.elt_watermark
    #                 (pipeline_name, source_name, source_table,
    #                  target_schema, target_table, watermark_column,
    #                  last_watermark_value, last_successful_batch_id, updated_at)
    #             VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
    #             ON CONFLICT ON CONSTRAINT uq_elt_watermark_pipeline_src DO UPDATE
    #                 SET last_watermark_value     = EXCLUDED.last_watermark_value,
    #                     last_successful_batch_id = EXCLUDED.last_successful_batch_id,
    #                     updated_at               = NOW()
    #             """,
    #             (pipeline_name, source_name, source_table,
    #              target_schema, target_table, watermark_column,
    #              str(new_watermark_value), batch_id),
    #         )
    #     conn.commit()

    logger.warning("PLACEHOLDER: update_watermark skipped — wire in real DB query.")
