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

import re
from datetime import datetime
from typing import Any

import pandas as pd
from sqlalchemy import text

from ingestion.utils.logger import get_logger
from ingestion.utils.watermark import get_watermark

logger = get_logger(__name__)

# Table/column names are SQL identifiers and cannot be bound parameters, so the
# extractor accepts only plain identifiers — keeping injection off the table when
# a name reaches the SQL string (MED-1). The watermark VALUE is always bound.
_SAFE_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


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
            sql, params = self._build_incremental_query(
                table_name, watermark_column, last_value
            )
        else:
            sql, params = self._build_full_load_query(table_name)

        logger.debug("Extraction SQL: %s | params: %s", sql, params)

        df = pd.read_sql(sql, con=self._get_connection(), params=params or None)
        logger.info("Extracted %d rows from %s", len(df), table_name)
        return df

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _validate_identifier(name: str, kind: str) -> str:
        """Reject anything that is not a plain SQL identifier (MED-1).

        Table and column names cannot be bound parameters, so this guards the
        one place a name reaches the SQL string. In the pipeline these come from
        ingestion_config.yml (already an allowlist); this is the reusable-class
        safety net for any direct or future caller.
        """
        if not isinstance(name, str) or not _SAFE_IDENTIFIER.match(name):
            raise ValueError(
                f"Unsafe {kind} identifier {name!r}: expected a plain SQL "
                "identifier matching [A-Za-z_][A-Za-z0-9_]*"
            )
        return name

    def _build_full_load_query(self, table_name: str) -> tuple[Any, dict[str, Any]]:
        """Build a full-load SELECT query (identifier validated; no params)."""
        # TODO: add schema prefix from config if needed
        self._validate_identifier(table_name, "table")
        return text(f"SELECT * FROM {table_name}"), {}

    def _build_incremental_query(
        self,
        table_name: str,
        watermark_column: str,
        last_value: str | datetime | None,
    ) -> tuple[Any, dict[str, Any]]:
        """Build an incremental SELECT filtering on the watermark.

        The watermark VALUE is a **bound parameter** (`:watermark`), never
        interpolated — so the driver sends it with its real type (no fragile
        str() round-trip) and there is no value-injection surface. Table/column
        are SQL identifiers (cannot be bound) and are validated first (MED-1).
        """
        self._validate_identifier(table_name, "table")
        if last_value is None:
            # No previous run — extract everything.
            return text(f"SELECT * FROM {table_name}"), {}
        self._validate_identifier(watermark_column, "watermark column")
        return (
            text(f"SELECT * FROM {table_name} WHERE {watermark_column} > :watermark"),
            {"watermark": last_value},
        )

    def _get_connection(self) -> Any:
        """Return an existing connection/engine or open one from env vars."""
        if self._connection is None:
            from ingestion.utils.database import get_oltp_engine

            self._connection = get_oltp_engine()
        return self._connection
