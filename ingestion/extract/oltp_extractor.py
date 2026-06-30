"""
oltp_extractor.py
-----------------
Placeholder class for extracting raw data from an OLTP source system.

Responsibilities (Python / ingestion layer):
  - Connect to the source OLTP database.
  - Read data using a watermark for incremental loads, or in full.
  - Return a pandas DataFrame of raw records with NO business transformation.

NOT responsible for:
  - Writing to silver or gold.
  - Applying business rules, calculations, or lookups.
  - Anything that dbt should own.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import pandas as pd

from ingestion.utils.logger import get_logger
from ingestion.utils.watermark import get_watermark

logger = get_logger(__name__)


class OLTPExtractor:
    """
    Extracts raw records from an OLTP source database.

    Parameters
    ----------
    source_name : str
        Logical name for the source system (e.g. 'oltp_printtime').
        Carried as lineage; watermarks are tracked in audit.etl_batch_control.
    pipeline_name : str
        Parent pipeline identifier for watermark lookups.
    connection : Any, optional
        A live database connection. If None, the extractor will open one
        using environment-variable credentials when extract_table() is called.
    """

    def __init__(
        self,
        source_name: str,
        pipeline_name: str,
        connection: Any = None,
    ) -> None:
        self.source_name = source_name
        self.pipeline_name = pipeline_name
        self._connection = connection

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def extract_table(
        self,
        table_name: str,
        watermark_column: str = "updated_at",
        strategy: str = "incremental",
    ) -> pd.DataFrame:
        """
        Extract all (or new/changed) rows from the given OLTP table.

        Parameters
        ----------
        table_name : str
            Source table name (unqualified; schema added from config).
        watermark_column : str
            Column used to filter new rows for incremental loads.
        strategy : str
            'full_load'  — SELECT * (no filter, replaces target)
            'incremental' — SELECT * WHERE <watermark_column> > <last_value>

        Returns
        -------
        pd.DataFrame
            Raw extracted data. No business transformations applied.
        """
        logger.info(
            "Extracting | source=%s table=%s strategy=%s",
            self.source_name,
            table_name,
            strategy,
        )

        if strategy == "incremental":
            last_value = get_watermark(
                pipeline_name=self.pipeline_name,
                source_name=self.source_name,
                source_table=table_name,
            )
            logger.info("Watermark value: %s", last_value)
            sql = self._build_incremental_query(
                table_name, watermark_column, last_value
            )
        else:
            sql = self._build_full_load_query(table_name)

        logger.debug("Extraction SQL: %s", sql)

        df = pd.read_sql(sql, con=self._get_connection())
        logger.info("Extracted %d rows from %s", len(df), table_name)
        return df

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _build_full_load_query(self, table_name: str) -> str:
        """Build a full-load SELECT query."""
        # TODO: add schema prefix from config if needed
        return f"SELECT * FROM {table_name}"

    def _build_incremental_query(
        self,
        table_name: str,
        watermark_column: str,
        last_value: str | datetime | None,
    ) -> str:
        """Build an incremental SELECT query filtering on watermark."""
        if last_value is None:
            # No previous run — extract everything
            return f"SELECT * FROM {table_name}"
        return (
            f"SELECT * FROM {table_name} " f"WHERE {watermark_column} > '{last_value}'"
        )

    def _get_connection(self) -> Any:
        """Return an existing connection/engine or open one from env vars."""
        if self._connection is None:
            from ingestion.utils.database import get_oltp_engine

            self._connection = get_oltp_engine()
        return self._connection
