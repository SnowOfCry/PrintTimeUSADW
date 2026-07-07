# ADR-008: Consolidate ETL Batch Control into the Audit Schema

- **Status:** Accepted
- **Date:** 2026-06-30
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

A readiness review found that "the batch control table" had **three competing identities** that had drifted apart during early development:

| Identity | Where it lived | State |
|---|---|---|
| `control.elt_batch_log` + `control.elt_watermark` | Docker init scripts → deployed in the DW | Deployed, empty — nothing wrote to them |
| `control.etl_batch_control` | Referenced 43× in bronze DDL comments and docs | Never existed |
| `audit.etl_batch_control` + `audit.audit_log` | `sql/audit/` DDL, per the Gold Schema diagram | Written, not deployed |

Bronze rows stamp a `bronze_batch_id` that is supposed to join to "the batch table" — but the docs pointed at a table that didn't exist, the deployed tables were never written to, and the designed tables weren't deployed. Any of the three could work; having all three guaranteed confusion.

## Decision

**Standardize on the `audit` schema as designed in the Gold Schema diagram** (evaluated as "Option A"):

- `audit.etl_batch_control` — one row per ETL batch: status lifecycle (`running` → `succeeded`/`failed`), row counts, and the **watermark window embedded on the batch row** (`watermark_column`, `watermark_value_start/end`). `batch_key` (identity) is what `bronze_batch_id` references; `batch_id` (unique text) is the external identifier.
- `audit.audit_log` — generic insert-only change trail (JSONB before/after images), which the `control` design had no equivalent for.
- The `control` schema was **dropped**; the Docker init now bootstraps the audit tables; the 43 doc/DDL references were repointed `control.` → `audit.`; the pipeline (`batch_control.py`, `watermark.py`) writes and reads `audit.etl_batch_control`.

## Alternatives considered

1. **Option B — keep `control` as the schema, create `etl_batch_control` inside it.** Fewer doc edits (docs already said `etl_batch_control`), but diverges from the Gold Schema diagram — the project's authoritative design — and still required deploying a new table. Rejected: matching the published spec was worth more than saving a find-and-replace.
2. **Option C — keep the deployed `control.elt_batch_log` + `elt_watermark` and rewrite the docs to match.** Least new SQL, and a *dedicated* watermark table is the classic pattern with slightly cleaner lookups. Rejected: it locks in scaffolding names that contradict the spec, requires a semantic rename across 43 references (`etl_batch_control` → `elt_batch_log`, more error-prone than a schema-prefix swap), and abandons `audit_log` — losing change-trail capability the design calls for.

## Consequences

**Positive**

- One canonical identity: spec (diagram), DDL, docs, Docker bootstrap, pipeline code, and the live database all name the same tables.
- Richer telemetry than the retired design: load type, watermark window, extracted/inserted/updated/deleted/rejected counts, retry count, initiator.
- Gained the insert-only `audit.audit_log` change trail.
- Verified in the same change: a full 20-table ingest recorded 20 `succeeded` batches (668,252 rows), with per-table watermarks captured and every bronze row joining `batch_key`.

**Negative / accepted costs**

- **Watermark lookups are latest-batch queries** (`MAX(watermark_value_end)` for the target's last succeeded batch) instead of a one-row dedicated-table read. Accepted: indexed on `target_table`/`batch_status`; trivial at our batch counts.
- `batch_id` is `VARCHAR(50)`, which constrains identifier formats (a too-long format was caught and shortened during implementation).
- One-time migration cost: schema drop, init replacement, 43 reference edits, pipeline rewiring — all completed and committed.

## Related

- ADR-004 (bronze rows stamp `bronze_batch_id` → `batch_key`), ADR-007 (gold loads log batches here too)
- `sql/audit/` — DDL; `docker/postgres/init/002_create_audit_tables.sql` — bootstrap
- `ingestion/utils/batch_control.py`, `ingestion/utils/watermark.py` — the lifecycle implementation
- `docs/dw_readiness_review.md` — the finding that triggered this decision
