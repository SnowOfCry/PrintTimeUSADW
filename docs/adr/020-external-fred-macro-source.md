# ADR-020: External Macroeconomic Source (FRED API) for Real-Terms Reporting

- **Status:** Accepted
- **Date:** 2026-08-13
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)

## Context

Every source so far is the OLTP Postgres database. The warehouse had no way to demonstrate — or
operate — **API ingestion**, and no external reference data to put its own numbers in context. Two
genuinely useful, finance-relevant questions were unanswerable:

1. **Real vs. nominal growth** — 2020-2025 spans high inflation, so nominal revenue overstates
   real growth. Deflating by CPI separates the two.
2. **Input-cost pressure** — the shop's COGS is dominated by paper, so tracking gross margin
   against a pulp/paper price index shows real cost pressure (notably on the thin-margin 4over
   catalog).

Both need an external economic series. FX rates were considered and **rejected**: the business is
USD-only with all-US customers, so FX would be a contrived bolt-on with no real use here.

## Decision

Add **FRED** (Federal Reserve Bank of St. Louis) as the warehouse's first **API source**, tracking:

- `CPIAUCSL` — CPI-U, All Items, seasonally adjusted → real-terms revenue.
- `WPU0911` — PPI, Pulp/Paper & Allied Products → input-cost pressure.

It flows through the same medallion + governance machinery as every other source:

| Concern | Decision |
|---|---|
| **Extraction** | `ingestion/extract/fred_extractor.py` — stdlib HTTP (no new dependency), timeout + bounded retry/backoff, incremental `observation_start`, FRED's `.` → NULL. |
| **Secret** | `FRED_API_KEY` from env only, fails loud if unset (MED-8 fail-closed pattern), forwarded to containers, never committed. |
| **Landing** | `bronze.econ_indicator`, append-only (ADR-004), watermark on `updated_at_source_timestamp` (= observation date). |
| **Silver** | `silver.econ_indicator`, contract-enforced incremental merge, composite key `(series_id, observation_date)`, hash-gated. |
| **Serving** | `gold.bi_revenue_real` (nominal vs CPI-deflated real revenue) and `gold.bi_margin_vs_paper_cost` (margin vs paper PPI). |
| **Orchestration** | DAG task `ingest_fred_to_bronze`, parallel with the OLTP ingest; silver waits for both; tests still gate the watermark (HIGH-7). |
| **DQ** | one row per (series, date); no month gaps; values positive; and every revenue month has a CPI basis at/before it (referential, forward-fill aware). |

### Deflation method

Real revenue is expressed in the **latest CPI month in the revenue window** ("today's dollars"):
`real = nominal × (base_cpi / month_cpi)`. Where FRED has a gap (CPI-U published **no Oct-2025
value**), the index is **forward-filled** with the last-known value rather than inner-joined — an
inner join silently dropped that month's revenue, which is worse than a visible gap. The referential
DQ test asserts the forward-fill always has a basis.

## Consequences

**Positive**
- Demonstrates and operates real **API ingestion** (secrets, retries, incremental) on the existing
  architecture — no new infrastructure.
- Adds two defensible finance analyses on the warehouse's own data.
- A time-series joined *as-of month* reuses the effective-dating pattern already central to the DW.

**Negative / bounded**
- FRED requires a free API key (a registration step); the pipeline fails loud without it.
- Monthly series lag publication (freshness SLA widened to 35d warn / 45d error accordingly).
- Occasional FRED revisions/gaps are handled (hash-gated merge absorbs revisions; forward-fill
  covers gaps), but the deflator is only as current as FRED's latest release.

## Related

- ADR-004 (bronze append-only), ADR-006 (silver merge), ADR-017 (BI serving layer),
  `docs/guides/cdc.md`, `docs/fix/fix_log.md`, `docs/audit/` (MED-8 secret pattern).
