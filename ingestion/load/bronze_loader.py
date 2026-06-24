"""
bronze_loader.py
----------------
Placeholder class for loading raw extracted data into the bronze schema.

Responsibilities (Python / ingestion layer):
  - Accept a pandas DataFrame of raw records.
  - Write the records to the correct bronze.<target_table>.
  - Apply ONLY minimal technical handling needed to write to Postgres
    (e.g. type coercion for column compatibility, not business logic).
  - Log start/end counts and status to control.elt_batch_log.
  - Update control.elt_watermark after a successful load.

NOT responsible for:
  - Cleaning, standardizing, or deduplicating data (that is dbt/silver).
  - Building business entities or metrics (that is dbt/gold).
"""

from __future__ import annotations

from typing import Any, Literal

import pandas as pd

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)


class BronzeLoader:
    """
    Writes a raw DataFrame into the bronze schema of the data warehouse.

    Parameters
    ----------
    pipeline_name : str
        Used to correlate this load with control.elt_batch_log.
    target_table : str
        Destination table name inside the bronze schema (without schema prefix).
    dw_engine : Any, optional
        A SQLAlchemy engine connected to the DW. Created from env vars if None.
    """

    def __init__(
        self,
        pipeline_name: str,
        target_table: str,
        dw_engine: Any = None,
    ) -> None:
        self.pipeline_name = pipeline_name
        self.target_table = target_table
        self._engine = dw_engine

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def load_dataframe_to_bronze(
        self,
        df: pd.DataFrame,
        strategy: str = "incremental",
        batch_id: int | None = None,
    ) -> int:
        """
        Write a DataFrame into bronze.<target_table>.

        Parameters
        ----------
        df : pd.DataFrame
            Raw extracted data. No business transformations should be applied
            before calling this method.
        strategy : str
            'full_load'   — truncate + insert (replaces target table).
            'incremental' — append new rows.
            'upsert'      — merge by primary key (requires pk_columns config).
        batch_id : int, optional
            Existing batch log ID to update. Creates a new record if None.

        Returns
        -------
        int
            Number of rows written to bronze.
        """
        if df.empty:
            logger.warning(
                "Empty DataFrame received | pipeline=%s table=bronze.%s — skipping load.",
                self.pipeline_name,
                self.target_table,
            )
            return 0

        rows = len(df)
        logger.info(
            "Loading %d rows → bronze.%s | strategy=%s",
            rows,
            self.target_table,
            strategy,
        )

        engine = self._get_engine()

        if_exists: Literal["replace", "append"] = (
            "replace" if strategy == "full_load" else "append"
        )
        df.to_sql(
            name=self.target_table,
            con=engine,
            schema="bronze",
            if_exists=if_exists,
            index=False,
            method="multi",
            chunksize=1000,
        )

        logger.info(
            "Loaded %d rows → bronze.%s | if_exists=%s",
            rows,
            self.target_table,
            if_exists,
        )
        return rows

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _get_engine(self) -> Any:
        """Return an existing SQLAlchemy engine or create one from env vars."""
        if self._engine is None:
            from ingestion.utils.database import get_dw_engine

            self._engine = get_dw_engine()
        return self._engine
