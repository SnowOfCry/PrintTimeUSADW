"""
main.py
-------
Entry point for running ingestion jobs outside of Airflow
(e.g. local development, manual backfills, or CLI invocation).

Usage:
    python -m ingestion.main --pipeline example --table orders

This file wires together extraction and loading without any
business transformation logic — that responsibility belongs to dbt.
"""

from __future__ import annotations

import argparse
import sys

import pandas as pd

from ingestion.utils.logger import get_logger
from ingestion.utils.config_loader import load_config

logger = get_logger(__name__)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PrintTimeUSA ELT Ingestion Runner")
    parser.add_argument(
        "--pipeline",
        required=True,
        help="Logical pipeline name (recorded on audit.etl_batch_control rows).",
    )
    parser.add_argument(
        "--table",
        required=True,
        help="Source table to extract (e.g. 'orders').",
    )
    parser.add_argument(
        "--strategy",
        choices=["full_load", "incremental"],
        default="incremental",
        help="Load strategy. Default: incremental.",
    )
    return parser.parse_args(argv)


def run(pipeline_name: str, table_name: str, strategy: str) -> None:
    """
    Orchestrate a single extraction + bronze load cycle under one ETL batch.

    Steps:
        1. Load configuration and resolve the Bronze target + watermark column.
        2. Open a batch in audit.etl_batch_control (status 'running').
        3. Extract data from the OLTP source (incremental uses the watermark).
        4. Append raw data into bronze, stamping bronze_batch_id = batch_key.
        5. Complete the batch (status 'succeeded', row counts, new watermark) —
           or mark it failed on error.

    Parameters
    ----------
    pipeline_name : str
        Logical identifier for this pipeline run.
    table_name : str
        Source table to extract.
    strategy : str
        'full_load' or 'incremental'.
    """
    logger.info(
        "Starting ingestion | pipeline=%s table=%s strategy=%s",
        pipeline_name,
        table_name,
        strategy,
    )

    from ingestion.extract.oltp_extractor import OLTPExtractor
    from ingestion.load.bronze_loader import BronzeLoader
    from ingestion.utils.batch_control import complete_batch, fail_batch, start_batch
    from ingestion.utils.database import get_dw_engine

    config = load_config()

    # Resolve the Bronze landing table from config (matches the sql/bronze DDL:
    # OLTP entities -> oltp_*, reference data -> ref_*). Fail loudly if a source
    # table has no mapping rather than silently inventing a raw_* table.
    table_cfg = next(
        (t for t in config.get("tables", []) if t.get("name") == table_name),
        None,
    )
    if table_cfg is None or not table_cfg.get("bronze_table"):
        raise ValueError(
            f"No 'bronze_table' mapping for source table '{table_name}' in "
            "ingestion_config.yml"
        )
    target_table = table_cfg["bronze_table"]
    watermark_column = table_cfg.get("watermark_column")
    source_system = "ref" if target_table.startswith("ref_") else "oltp"
    load_type = "incremental_append" if strategy == "incremental" else "full_load"

    # Reuse one DW engine for the batch + load.
    engine = get_dw_engine()

    # 2. Open the batch.
    batch_key, batch_id = start_batch(
        pipeline_name=pipeline_name,
        source_system=source_system,
        target_table=target_table,
        load_type=load_type,
        watermark_column=watermark_column,
        engine=engine,
    )

    try:
        # 3. Extract (incremental reads the watermark via get_watermark).
        extractor = OLTPExtractor(
            source_name=config["source_name"],
            pipeline_name=pipeline_name,
        )
        df = extractor.extract_table(
            table_name=table_name,
            watermark_column=watermark_column or "updated_at",
            strategy=strategy,
        )

        # New high-water mark = max of the source watermark column in this batch.
        watermark_value_end: str | None = None
        if watermark_column and not df.empty and watermark_column in df.columns:
            max_wm = df[watermark_column].max()
            watermark_value_end = None if pd.isna(max_wm) else str(max_wm)

        # 4. Append into Bronze, stamping bronze_batch_id = batch_key.
        loader = BronzeLoader(
            pipeline_name=pipeline_name,
            target_table=target_table,
            source_table_name=table_name,
            source_system=source_system,
            batch_id=batch_key,
            dw_engine=engine,
        )
        rows_loaded = loader.load_dataframe_to_bronze(
            df=df, strategy=strategy, batch_id=batch_key
        )

        # 5. Complete the batch.
        complete_batch(
            batch_key=batch_key,
            rows_extracted=len(df),
            rows_inserted=rows_loaded,
            watermark_value_end=watermark_value_end,
            engine=engine,
        )
    except Exception as exc:
        fail_batch(batch_key, str(exc), engine=engine)
        raise

    logger.info(
        "Ingestion complete | pipeline=%s table=%s batch=%s rows_loaded=%d",
        pipeline_name,
        table_name,
        batch_id,
        rows_loaded,
    )


def main() -> None:
    args = parse_args()
    try:
        run(
            pipeline_name=args.pipeline,
            table_name=args.table,
            strategy=args.strategy,
        )
    except Exception:
        logger.exception("Ingestion failed — see traceback above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
