# ADR-004: Bronze Is Append-Only (Immutable Raw History)

- **Status:** Accepted
- **Date:** 2026-04-15
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

Bronze is the landing layer for everything extracted from the OLTP (ADR-001). The decision here is what happens when a source row **changes**: invoice 1001 is extracted as OPEN on Monday, PARTIAL on Tuesday, PAID on Friday. Does bronze keep one row per invoice (overwritten each time), or every version it has ever seen?

This matters because two core requirements depend on it: **SCD2 dimensions in gold** need the change history to build versions from, and **auditability** requires being able to answer "what exactly did the source say, and when?" long after the fact. The invoice status lifecycle (OPEN → PARTIAL → PAID → VOID) is the canonical business case.

## Decision

Bronze is **append-only and immutable**. Every extract performs `INSERT` only — never `UPDATE`, `DELETE`, or `MERGE`. A changed source row is appended as a **new bronze row** alongside its older versions.

Supporting design choices that follow from this:

- **The technical PK is `bronze_record_id` (BIGSERIAL), not the source id.** Invoice 1001 legitimately appears many times; making `invoice_id` the PK would reject the second version and destroy the history the layer exists to keep.
- **Watermark-driven extraction** (`updated_at` / `changed_at` per table) pulls only new/changed rows each run; tiny static reference tables are re-extracted in full and appended as a snapshot under a new batch id — never `TRUNCATE`+reload.
- **Every row is stamped** with `bronze_batch_id` (→ `audit.etl_batch_control`), load/extract timestamps, `bronze_row_hash` (hash of business columns for downstream change detection), and the full raw payload as JSONB.
- Deletes are captured as **soft-delete flags** (`is_deleted_source_flag`, `bronze_is_deleted_flag`), never physical removal.

## Alternatives considered

1. **Upsert-in-place bronze (one current row per business key).** Rejected: it turns bronze into a copy of the source's current state — which is exactly silver's job (ADR-006). History would be lost the moment it is overwritten; SCD2 in gold would then depend on catching every change between runs, and any missed run would silently lose invoice-status transitions forever.
2. **Full snapshot-replace (truncate and reload every run).** Rejected: loses all history between snapshots, and re-extracting large tables (`invoice_line`, ~390k rows) in full every run puts pointless load on the operational system that the watermark approach avoids.
3. **Rely on the source's own change log (`audit_log` CDC table in the OLTP).** The OLTP schema includes an application-populated `audit_log`. Rejected as the *foundation* for history: the warehouse would then depend on the application reliably writing its own CDC for every table forever — a guarantee we cannot enforce. Bronze's append-only history is self-sufficient; the source's `invoice_status_history` / `customer_status_history` tables are still extracted as an authoritative *cross-check* for status timelines.

## Consequences

**Positive**

- A complete, immutable change feed: SCD2, audits, and rule-change reprocessing (ADR-003) never require re-extracting from the OLTP.
- Failed batches can be identified and superseded by `bronze_batch_id` without mutating prior rows.
- Load logic stays trivially simple (filter on watermark, insert) — no merge edge cases in the most failure-sensitive layer.

**Negative / accepted costs**

- **Storage grows monotonically.** Accepted at our volumes; a retention/archival policy for old bronze versions is deferred until size warrants it.
- **Every consumer must deduplicate.** The same business row appears many times, so silver must always collapse to latest-version-per-key (`ROW_NUMBER` over the watermark ordering — specified in the silver merge strategy).
- **Full-snapshot reference tables stack identical versions** each run. Accepted as harmless at their size (3–8 rows each); a hash-based "skip unchanged snapshot" optimization is a known future refinement.

## Related

- ADR-001 (medallion), ADR-003 (ELT), ADR-006 (silver merge — the deduplicating consumer)
- `docs/load_strategy/bronze_incremental_append_strategy.md` — full mechanics (watermarks, batch ids, hashes)
- `sql/bronze/002_create_bronze_tables.sql` — `bronze_record_id` PK and metadata block
