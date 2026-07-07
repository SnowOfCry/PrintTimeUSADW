# ADR-003: ELT over ETL — Python Extracts and Loads Only; All Transformations Run Inside the Warehouse

- **Status:** Accepted
- **Date:** 2026-04-08
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

With the medallion architecture chosen (ADR-001), the next decision was **where transformation logic lives**. Two places compete for it:

- **In the pipeline code (ETL):** Python cleans, joins, and shapes the data *before* loading it into the warehouse.
- **In the warehouse (ELT):** Python only extracts source rows and lands them raw; all cleaning, standardization, and dimensional modeling run as SQL inside PostgreSQL (silver and gold builds, orchestrated by Airflow, with dbt as the transformation framework).

What made this decision matter here: business rules for this warehouse are expected to evolve (status vocabularies, derived flags like `paid_in_full_flag`, margin logic), and the bronze layer's whole purpose (ADR-004) is to preserve raw history so rules can be re-applied without touching the operational system.

## Decision

**ELT.** The division of responsibility is strict and documented in the ingestion code itself:

| Python (ingestion layer) owns | SQL in the warehouse owns |
|---|---|
| Connecting to the OLTP source | Cleaning, casting, deduplicating (silver) |
| Watermark-based incremental extraction | Business rules, status vocabularies, derived flags |
| Landing raw rows into bronze with lineage metadata | Surrogate keys, SCD2, dimensions, facts (gold) |
| Batch logging to `audit.etl_batch_control` | Data-quality checks and metrics |

Python performs **zero business transformation** — only technical standardization required to land rows (column renaming to bronze conventions, metadata stamping, row hashing).

## Alternatives considered

1. **Classic ETL (transform in Python before loading).** Rejected. When a business rule changes under ETL, the corrected data exists nowhere — you must re-extract from the operational system and re-run the pipeline. Under ELT, re-running SQL against bronze reprocesses history for free. ETL also splits business logic across two languages, so answering "why does this number look like this?" requires reading Python *and* SQL; under ELT, all business logic is SQL, versioned and testable in one place.
2. **Managed ingestion SaaS (Fivetran / Airbyte Cloud) + dbt.** The modern default for multi-source stacks, and it enforces ELT by design. Rejected here: we have exactly one source (a PostgreSQL OLTP we control), so a connector service adds recurring cost and an external dependency to replace ~200 lines of extractor code we already needed for watermark and batch-control integration. Revisit if source count grows (SaaS APIs, CSV feeds from suppliers like 4over).
3. **Real-time CDC streaming (e.g., Debezium/Kafka).** Rejected: the business cadence is daily; streaming infrastructure would add substantial operational complexity (ADR-002 accepted a one-engineer operations budget) for freshness nobody asked for.

## Consequences

**Positive**

- **Rule changes are cheap:** edit SQL, re-run against bronze — no re-extraction, no OLTP impact.
- **One home for business logic** (SQL), reviewable and testable; the transformation layer can adopt dbt tests and docs directly.
- **Transforms scale with the database engine,** not with the Python process (already proven relevant: the 390k-row `invoice_line` load exhausted pipeline memory and had to be chunked — logic pushed to SQL avoids that class of problem entirely).

**Negative / accepted costs**

- The warehouse does double duty (storage + transform compute). Accepted at our volumes; becomes a cloud-migration argument, not a redesign, if it ever binds (ADR-002 revisit triggers).
- Raw data lands before validation, so bad source data enters bronze. Accepted deliberately: bronze is *supposed* to be a faithful record; quality gates belong at the silver boundary (ADR-012, data quality).
- Requires discipline to keep business logic out of Python. Mitigated by documenting the responsibility split in the ingestion module docstrings and enforcing it in code review.

## Related

- ADR-001 (medallion), ADR-004 (bronze append-only), ADR-012 (data quality)
- `README.md` §3 — "Why ELT Instead of ETL"
- `ingestion/` — module docstrings state the Python/SQL responsibility split
