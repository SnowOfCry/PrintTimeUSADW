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

from ingestion.utils.logger import get_logger
from ingestion.utils.config_loader import load_config

logger = get_logger(__name__)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PrintTimeUSA ELT Ingestion Runner")
    parser.add_argument(
        "--pipeline",
        required=True,
        help="Logical pipeline name (matches control.elt_batch_log.pipeline_name).",
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
    Orchestrate a single extraction + bronze load cycle.

    Steps:
        1. Load configuration.
        2. Extract data from the OLTP source.
        3. Load raw data into bronze.
        4. Update control.elt_batch_log and control.elt_watermark.

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

    config = load_config()

    extractor = OLTPExtractor(
        source_name=config["source_name"],
        pipeline_name=pipeline_name,
    )
    df = extractor.extract_table(table_name=table_name, strategy=strategy)

    loader = BronzeLoader(
        pipeline_name=pipeline_name,
        target_table=f"raw_{table_name}",
    )
    rows_loaded = loader.load_dataframe_to_bronze(df=df, strategy=strategy)

    logger.info(
        "Ingestion complete | pipeline=%s table=%s rows_loaded=%d",
        pipeline_name,
        table_name,
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
