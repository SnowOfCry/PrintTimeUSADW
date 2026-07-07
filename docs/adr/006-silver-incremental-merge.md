# ADR-006: Silver Load Strategy — Incremental Merge to One Current Row per Business Key

- **Status:** Accepted
- **Date:** 2026-05-14
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

Bronze is an append-only change feed (ADR-004): the same invoice appears once per extracted version. Silver must present clean entities to gold — which raises two questions: **how many versions does silver keep**, and **how do bronze's stacked versions collapse into silver rows** efficiently, run after run?

## Decision

Silver keeps **exactly one clean, current row per business key**, maintained by an **incremental, hash-gated merge**:

1. **Read only new bronze rows** — `bronze_batch_id > :last_successful_batch_id` (watermark from `audit.etl_batch_control`).
2. **Deduplicate to the latest version per key** with a window function: `ROW_NUMBER()` partitioned by the business key, ordered by `updated_at_source_timestamp DESC` (event time `changed_at` for the two history tables), tie-broken by bronze load time and `bronze_record_id` — deterministic by construction. Keep `rn = 1`.
3. **Upsert on the business key** (`INSERT … ON CONFLICT (silver_<entity>_id) DO UPDATE`), but **only when the row truly changed**: `WHERE silver.silver_row_hash IS DISTINCT FROM EXCLUDED.silver_row_hash`. The hash is computed over the *cleaned* values (ADR-005), so cosmetic source noise does not fire updates.
4. `silver_created_at_timestamp` is set once on insert; `silver_updated_at_timestamp` advances only on a real update; lineage columns point to the winning bronze row.

**Deliberate exception:** `silver.invoice_status_history` and `silver.customer_status_history` are **history-tracked** — one row per transition, never collapsed — because status timelines are themselves the business record (they feed SCD2 `dim_invoice` and customer-status analysis in gold).

## Alternatives considered

1. **SCD2 in silver (keep all versions).** Rejected: it duplicates work — bronze already holds full history, and gold owns curated SCD2 (ADR-007). A versioned silver would make every gold load (and every ad-hoc query) filter `is_current`, for no information gain over bronze + gold.
2. **Full rebuild each run (truncate silver, rebuild from bronze).** Rejected: bronze grows forever, so the rebuild cost grows forever too; row timestamps would reset on every run, destroying downstream change detection; and a mid-rebuild failure leaves silver empty rather than stale — stale is recoverable, empty breaks BI.
3. **Blind upsert (update on every key conflict, no hash gate).** Simpler SQL, rejected: every run would rewrite every extracted row, `silver_updated_at_timestamp` would advance without business change, and gold could no longer trust "updated since last run" as a change signal. The hash gate is what keeps downstream incremental logic honest.

## Consequences

**Positive**

- Silver stays small and query-friendly (one row per entity), making gold loads simple and fast.
- Idempotent and re-runnable: re-processing the same bronze batches produces zero duplicates and zero spurious updates.
- Cheap runs: work is proportional to *changed* rows, not table size.

**Negative / accepted costs**

- **Silver holds no history** (except the two history tables). Gold SCD2 can only version what it observes between runs — if an attribute changes twice between gold loads, the intermediate state collapses. Accepted for slow-moving dimensions; for the case where every transition matters (invoice status), the history tables preserve the full timeline.
- The merge requires the business key as silver's primary key — constrains the DDL (already so designed).
- Deletes are logical only (`silver_is_deleted_flag`); consumers must filter, never assume physical removal.

## Related

- ADR-004 (bronze append-only — the input), ADR-005 (cleaning standards — what gets hashed), ADR-007 (gold loads — the consumer)
- `docs/load_strategy/silver_incremental_merge_strategy.md` — full mechanics with SQL sketches
- `sql/silver/002_create_silver_tables.sql` — business-key PKs, hash and lineage columns
