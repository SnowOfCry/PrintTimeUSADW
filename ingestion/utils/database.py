"""
database.py
-----------
PostgreSQL connection utilities for the ingestion layer.

All credentials are read from environment variables — never hardcoded.
"""

from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Generator

import psycopg2
import psycopg2.extras
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Data Warehouse (PostgreSQL) — used by BronzeLoader and watermark utilities
# ---------------------------------------------------------------------------

def get_dw_connection_string() -> str:
    """Build a PostgreSQL DSN from environment variables."""
    host     = os.environ["DW_HOST"]
    port     = os.environ.get("DW_PORT", "5432")
    database = os.environ["DW_DB"]
    user     = os.environ["DW_USER"]
    password = os.environ["DW_PASSWORD"]
    return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"


def get_dw_engine() -> Engine:
    """
    Return a SQLAlchemy engine connected to the data warehouse.

    Use this for pandas to_sql / read_sql operations.
    """
    dsn = get_dw_connection_string()
    engine = create_engine(dsn, pool_pre_ping=True, pool_size=2, max_overflow=4)
    logger.debug("DW engine created | host=%s", os.environ.get("DW_HOST"))
    return engine


@contextmanager
def get_dw_psycopg2_conn() -> Generator[psycopg2.extensions.connection, None, None]:
    """
    Context manager that yields a raw psycopg2 connection to the DW.

    Use this for control-table writes (batch log, watermark) where you need
    fine-grained transaction control.

    Example
    -------
    with get_dw_psycopg2_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE control.elt_batch_log SET status = %s ...", ("success",))
        conn.commit()
    """
    conn: psycopg2.extensions.connection | None = None
    try:
        conn = psycopg2.connect(
            host=os.environ["DW_HOST"],
            port=int(os.environ.get("DW_PORT", "5432")),
            dbname=os.environ["DW_DB"],
            user=os.environ["DW_USER"],
            password=os.environ["DW_PASSWORD"],
            cursor_factory=psycopg2.extras.RealDictCursor,
        )
        yield conn
    except psycopg2.Error:
        if conn:
            conn.rollback()
        logger.exception("DW connection error")
        raise
    finally:
        if conn and not conn.closed:
            conn.close()


# ---------------------------------------------------------------------------
# OLTP Source — placeholder; replace with real source credentials/driver
# ---------------------------------------------------------------------------

def get_oltp_connection() -> None:
    """
    Return a connection to the OLTP source system.

    Replace this stub with the correct driver and credentials for your
    source database (PostgreSQL, MySQL, MSSQL, etc.).
    Read credentials ONLY from environment variables.
    """
    # Example for a PostgreSQL OLTP source:
    # import psycopg2
    # return psycopg2.connect(
    #     host=os.environ["OLTP_HOST"],
    #     port=int(os.environ.get("OLTP_PORT", "5432")),
    #     dbname=os.environ["OLTP_DB"],
    #     user=os.environ["OLTP_USER"],
    #     password=os.environ["OLTP_PASSWORD"],
    # )
    raise NotImplementedError(
        "Wire in your OLTP source connection in database.get_oltp_connection()."
    )
