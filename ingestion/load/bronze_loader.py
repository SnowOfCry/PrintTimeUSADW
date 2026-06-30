"""
bronze_loader.py
----------------
Loads raw extracted OLTP/reference data into the bronze landing layer.

Responsibilities (Python / ingestion layer):
  - Accept a pandas DataFrame of raw source records (source column names).
  - Standardize source columns into the bronze column names (per the bronze
    data dictionary "Source / Origin" spec): timestamp/version/delete renames
    plus per-table business renames.
  - Stamp the required bronze metadata block (bronze_batch_id,
    bronze_source_system, bronze_source_table_name, bronze_extracted_at_timestamp,
    bronze_row_hash, bronze_is_deleted_flag, bronze_raw_payload_jsonb).
  - APPEND the rows into bronze.<target_table> (append-only; never replace).

NOT responsible for:
  - Cleaning, standardizing, or deduplicating business values (that is silver).
  - Building business entities or metrics (that is gold).
"""

from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Any

import pandas as pd
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import JSONB

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Source -> Bronze column renames (from docs/data_dictionary/bronze_data_dictionary.md).
# Applied to every table when the source column is present. The updated_at /
# source_updated_at collision is handled separately (coalesce) in _standardize.
# ---------------------------------------------------------------------------
GLOBAL_RENAMES: dict[str, str] = {
    "created_at": "created_at_source_timestamp",
    "changed_at": "changed_at_source_timestamp",
    "row_version": "source_row_version",
    "is_deleted": "is_deleted_source_flag",
    "deleted_at": "deleted_at_source_timestamp",
}

# Per-bronze-table business / flag renames.
PER_TABLE_RENAMES: dict[str, dict[str, str]] = {
    "oltp_customer_address": {"is_primary": "is_primary_flag"},
    "oltp_product": {
        "unit_cost": "unit_cost_amount",
        "standard_price": "standard_price_amount",
        "is_local_made": "is_local_made_flag",
        "is_active": "is_active_flag",
    },
    "oltp_product_category": {"is_active": "is_active_flag"},
    "oltp_department": {"is_active": "is_active_flag"},
    "oltp_employee": {"is_active": "is_active_flag"},
    "oltp_store": {"is_active": "is_active_flag"},
    "oltp_invoice": {
        "due_date": "invoice_due_date",
        "status_code": "invoice_status",
        "balance_due": "balance_due_amount",
    },
    "oltp_invoice_line": {
        "description": "line_description",
        "quantity": "order_qty",
        "unit_price": "unit_price_amount",
        "unit_cost": "unit_cost_amount",
        "extended_amount": "line_total_amount",
    },
    "oltp_payment": {"payment_sequence": "payment_sequence_num"},
    "ref_payment_method": {"is_card": "is_card_flag", "is_active": "is_active_flag"},
    "ref_payment_type": {"affects_balance": "affects_balance_flag"},
    "ref_tax_rate": {"is_active": "is_active_flag"},
    "ref_invoice_status": {"is_terminal": "is_terminal_flag"},
}

# Bronze metadata columns this loader stamps (excluded from the business hash).
_METADATA_COLS = {
    "bronze_batch_id",
    "bronze_source_system",
    "bronze_source_table_name",
    "bronze_source_file_name",
    "bronze_source_row_number",
    "bronze_extracted_at_timestamp",
    "bronze_row_hash",
    "bronze_is_deleted_flag",
    "bronze_raw_payload_jsonb",
}


class BronzeLoader:
    """
    Standardizes a raw source DataFrame and appends it to bronze.<target_table>.

    Parameters
    ----------
    pipeline_name : str
        Correlates this load with the batch control table.
    target_table : str
        Destination bronze table (e.g. 'oltp_customer', 'ref_state').
    source_table_name : str
        Original source table name (e.g. 'customer'); stamped as lineage.
    source_system : str, optional
        Source system label ('oltp' / 'ref'). Derived from target_table if None.
    batch_id : int, optional
        ETL batch id stamped onto every row. Generated if None.
    dw_engine : Any, optional
        SQLAlchemy engine for the DW. Created from env vars if None.
    """

    # Rows transformed + appended per chunk (bounds peak memory on big tables).
    LOAD_CHUNK_ROWS = 20000

    def __init__(
        self,
        pipeline_name: str,
        target_table: str,
        source_table_name: str | None = None,
        source_system: str | None = None,
        batch_id: int | None = None,
        dw_engine: Any = None,
    ) -> None:
        self.pipeline_name = pipeline_name
        self.target_table = target_table
        self.source_table_name = source_table_name or target_table
        self.source_system = source_system or (
            "ref" if target_table.startswith("ref_") else "oltp"
        )
        self.batch_id = (
            batch_id if batch_id is not None else int(datetime.now().timestamp())
        )
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
        Standardize and APPEND a raw source DataFrame into bronze.<target_table>.

        Bronze is append-only: `strategy` only documents how the rows were
        extracted (incremental vs full_load); the write is always an append.
        """
        if batch_id is not None:
            self.batch_id = batch_id

        if df.empty:
            logger.warning(
                "Empty DataFrame received | pipeline=%s table=bronze.%s — skipping load.",
                self.pipeline_name,
                self.target_table,
            )
            return 0

        engine = self._get_engine()
        target_cols = self._get_target_columns(engine)

        total = len(df)
        logger.info(
            "Appending %d rows → bronze.%s | strategy=%s batch_id=%s",
            total,
            self.target_table,
            strategy,
            self.batch_id,
        )

        # Transform + append in row-chunks so peak memory stays bounded on large
        # tables (e.g. invoice_line ~390k rows); transforming the whole frame at
        # once can exhaust container memory.
        loaded = 0
        for start in range(0, total, self.LOAD_CHUNK_ROWS):
            chunk = df.iloc[start : start + self.LOAD_CHUNK_ROWS]
            bronze_chunk = self._standardize(
                chunk, target_cols, log_diagnostics=(start == 0)
            )
            bronze_chunk.to_sql(
                name=self.target_table,
                con=engine,
                schema="bronze",
                if_exists="append",  # bronze is append-only — never replace
                index=False,
                method="multi",
                chunksize=500,
                dtype={"bronze_raw_payload_jsonb": JSONB},
            )
            loaded += len(bronze_chunk)

        logger.info(
            "Appended %d rows → bronze.%s (batch_id=%s)",
            loaded,
            self.target_table,
            self.batch_id,
        )
        return loaded

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _standardize(
        self,
        df: pd.DataFrame,
        target_cols: list[str],
        log_diagnostics: bool = False,
    ) -> pd.DataFrame:
        """Rename source columns to bronze names and stamp the metadata block."""
        # Keep the full raw row for the JSONB payload before any renaming.
        # Convert NaN/NaT -> None so the payload serializes to valid JSON
        # (PostgreSQL's json type rejects the NaN/Infinity literals Python emits).
        raw_payload = (
            df.astype(object).where(df.notna(), None).to_dict(orient="records")
        )

        work = df.copy()

        # Collapse updated_at / source_updated_at -> updated_at_source_timestamp.
        if "source_updated_at" in work.columns or "updated_at" in work.columns:
            su = (
                work["source_updated_at"]
                if "source_updated_at" in work.columns
                else None
            )
            ua = work["updated_at"] if "updated_at" in work.columns else None
            if su is not None and ua is not None:
                work["updated_at_source_timestamp"] = su.fillna(ua)
            elif su is not None:
                work["updated_at_source_timestamp"] = su
            else:
                work["updated_at_source_timestamp"] = ua
            work = work.drop(
                columns=[
                    c for c in ("source_updated_at", "updated_at") if c in work.columns
                ]
            )

        # Apply global + per-table renames (only for columns that exist).
        renames = {**GLOBAL_RENAMES, **PER_TABLE_RENAMES.get(self.target_table, {})}
        work = work.rename(
            columns={k: v for k, v in renames.items() if k in work.columns}
        )

        # Source soft-delete flag drives the bronze delete capture flag.
        if "is_deleted_source_flag" in work.columns:
            is_deleted_flag = work["is_deleted_source_flag"].fillna(False).astype(bool)
        else:
            is_deleted_flag = pd.Series(False, index=work.index)

        # Business columns = everything not in the metadata block, hashed for change detection.
        business_cols = sorted(c for c in work.columns if c not in _METADATA_COLS)
        hash_input = work[business_cols].astype(str).agg("|".join, axis=1)
        work["bronze_row_hash"] = hash_input.map(
            lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()
        )

        # Stamp the rest of the metadata block.
        work["bronze_batch_id"] = self.batch_id
        work["bronze_source_system"] = self.source_system
        work["bronze_source_table_name"] = self.source_table_name
        work["bronze_extracted_at_timestamp"] = datetime.now()
        work["bronze_is_deleted_flag"] = is_deleted_flag
        work["bronze_raw_payload_jsonb"] = raw_payload

        # Keep only columns that exist on the target bronze table; warn on drops/gaps.
        keep = [c for c in work.columns if c in target_cols]
        dropped = [c for c in work.columns if c not in target_cols]
        unfilled = [
            c
            for c in target_cols
            if c not in work.columns
            and c not in ("bronze_record_id", "bronze_loaded_at_timestamp")
        ]
        if log_diagnostics and dropped:
            logger.warning(
                "bronze.%s: source columns dropped (no bronze column): %s",
                self.target_table,
                dropped,
            )
        if log_diagnostics and unfilled:
            logger.warning(
                "bronze.%s: bronze columns left to default/NULL: %s",
                self.target_table,
                unfilled,
            )

        return work[keep]

    def _get_target_columns(self, engine: Any) -> list[str]:
        """Return the column names of bronze.<target_table> from the catalog."""
        sql = text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = 'bronze' AND table_name = :t ORDER BY ordinal_position"
        )
        with engine.connect() as conn:
            rows = conn.execute(sql, {"t": self.target_table}).fetchall()
        cols = [r[0] for r in rows]
        if not cols:
            raise ValueError(f"bronze.{self.target_table} does not exist in the DW")
        return cols

    def _get_engine(self) -> Any:
        """Return an existing SQLAlchemy engine or create one from env vars."""
        if self._engine is None:
            from ingestion.utils.database import get_dw_engine

            self._engine = get_dw_engine()
        return self._engine
