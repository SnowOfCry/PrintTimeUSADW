"""
fred_extractor.py
-----------------
Extract macroeconomic time series from the **FRED API** (Federal Reserve Bank of
St. Louis) into a raw DataFrame for the bronze layer.

This is the warehouse's first API source (all others are OLTP-Postgres). It
demonstrates the API-ingestion patterns that matter in practice:
  * secret handling — the API key is read from the FRED_API_KEY env var, never
    hard-coded (fail loud if missing);
  * resilience — timeout + bounded retry with backoff on transient errors;
  * incremental extraction — pull only observations dated after a watermark;
  * source hygiene — FRED encodes a missing value as ".", mapped to NULL here;
  * zero business transformation — bronze gets the raw observation as-is.

Returns a tidy DataFrame (one row per series/date) that BronzeLoader appends to
`bronze.econ_indicator`. No pandas-side cleaning beyond typing.

Docs: https://fred.stlouisfed.org/docs/api/fred/series_observations.html
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

import pandas as pd

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)

FRED_BASE_URL = "https://api.stlouisfed.org/fred/series/observations"

# The series this warehouse tracks (id -> human label + units). Adding a series
# is a one-line change here; the pipeline handles the rest.
DEFAULT_SERIES: dict[str, dict[str, str]] = {
    # CPI-U, All Items, seasonally adjusted (index 1982-84=100) — deflates
    # nominal revenue to real terms.
    "CPIAUCSL": {"label": "CPI (All Urban Consumers, SA)", "units": "index_1982_84"},
    # PPI by commodity: Pulp, paper & allied products — the shop's main input
    # cost; correlate against margin.
    "WPU0911": {"label": "PPI: Pulp, Paper & Allied Products", "units": "index"},
}


class FREDExtractor:
    """Pull observations for a set of FRED series into one raw DataFrame."""

    REQUEST_TIMEOUT = 30          # seconds
    MAX_RETRIES = 3
    RETRY_BACKOFF = 2.0           # seconds, multiplied by attempt number

    def __init__(
        self,
        series: dict[str, dict[str, str]] | None = None,
        api_key: str | None = None,
    ) -> None:
        self.series = series or DEFAULT_SERIES
        self.api_key = api_key or os.environ.get("FRED_API_KEY")
        if not self.api_key:
            raise ValueError(
                "FRED_API_KEY is not set. Get a free key at "
                "https://fredaccount.stlouisfed.org/apikeys and put it in .env."
            )

    # -- public ------------------------------------------------------------
    def extract(self, observation_start: str | None = None) -> pd.DataFrame:
        """Return observations for every configured series.

        Parameters
        ----------
        observation_start : str, optional
            'YYYY-MM-DD'. Only observations on/after this date are pulled
            (incremental). None => full history.
        """
        frames = [self._extract_series(sid, meta, observation_start)
                  for sid, meta in self.series.items()]
        df = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
        logger.info(
            "FRED extract complete | series=%d rows=%d start=%s",
            len(self.series), len(df), observation_start or "(all)",
        )
        return df

    # -- internals ---------------------------------------------------------
    def _extract_series(
        self, series_id: str, meta: dict[str, str], start: str | None
    ) -> pd.DataFrame:
        params = {
            "series_id": series_id,
            "api_key": self.api_key,
            "file_type": "json",
        }
        if start:
            params["observation_start"] = start
        payload = self._get(params, series_id)

        rows = []
        for obs in payload.get("observations", []):
            raw = obs.get("value", ".")
            # FRED encodes "missing" as "." — keep the row, NULL the value.
            value = None if raw in (".", "", None) else float(raw)
            rows.append({
                "series_id": series_id,
                "observation_date": obs.get("date"),
                "indicator_value": value,
                "units": meta.get("units"),
                # Business timestamps for the loader + watermark: the observation
                # date is the source's own "as-of" instant for this row.
                "created_at": obs.get("date"),
                "updated_at": obs.get("date"),
            })
        df = pd.DataFrame(rows)
        if not df.empty:
            df["observation_date"] = pd.to_datetime(df["observation_date"]).dt.date
            df["created_at"] = pd.to_datetime(df["created_at"])
            df["updated_at"] = pd.to_datetime(df["updated_at"])
        logger.info("  %s: %d observations", series_id, len(df))
        return df

    def _get(self, params: dict[str, str], series_id: str) -> dict:
        """GET with timeout + bounded retry/backoff on transient failures."""
        url = f"{FRED_BASE_URL}?{urllib.parse.urlencode(params)}"
        last_err: Exception | None = None
        for attempt in range(1, self.MAX_RETRIES + 1):
            try:
                with urllib.request.urlopen(url, timeout=self.REQUEST_TIMEOUT) as resp:  # noqa: S310
                    return json.loads(resp.read().decode("utf-8"))
            except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
                last_err = exc
                wait = self.RETRY_BACKOFF * attempt
                logger.warning(
                    "FRED request failed (series=%s attempt=%d/%d): %s — retrying in %.0fs",
                    series_id, attempt, self.MAX_RETRIES, exc, wait,
                )
                if attempt < self.MAX_RETRIES:
                    time.sleep(wait)
        raise RuntimeError(f"FRED request failed for {series_id} after "
                           f"{self.MAX_RETRIES} attempts: {last_err}")


def _redacted(msg: str) -> str:
    """Never let the API key reach a log line."""
    key = os.environ.get("FRED_API_KEY", "")
    return msg.replace(key, "***") if key else msg
