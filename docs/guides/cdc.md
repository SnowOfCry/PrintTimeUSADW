# Change Data Capture (CDC) — How It Works

How PrintTimeUSA detects and moves **only what changed** from the OLTP source into the
warehouse, run after run, without missing rows or double-counting them.

**Related:** [ADR-004](../adr/004-bronze-append-only.md) (bronze append-only),
[ADR-006](../adr/006-silver-incremental-merge.md) (silver merge),
[`docs/load_strategy/`](../load_strategy/), [`docs/fix/fix_log.md`](../fix/fix_log.md) (FIX-016),
[SCD guide](scd.md).

---

## 1. The strategy in one sentence

This is **timestamp-based, watermark-driven CDC**: each source table exposes a monotonic
`updated_at`, ingestion remembers the highest value it has already loaded (the *watermark*), and
each run extracts only rows with `updated_at > watermark`. Reference/dimension tables that are too
small to bother watermarking are **full-loaded** and de-duplicated by a row hash instead.

There is no log-based CDC (no Debezium / WAL decoding) — deliberately. For a single source at this
volume, timestamp CDC is simpler, has no extra moving parts, and is easy to reason about and audit.

## 2. Two load strategies (see `ingestion/config/ingestion_config.yml`)

| Strategy | Used for | How "what changed" is decided |
|---|---|---|
| **incremental** | large transactional tables (`invoice`, `invoice_line`, `payment`, …) | `updated_at > watermark` (a `changed_at` variant for the history tables) |
| **full_load** | small reference/dimension tables (`ref_*`, `product`, `store`, …) | re-read the whole table every run; skip rows whose row-hash already exists |

## 3. The watermark

- Lives in **`audit.etl_batch_control`** — one row per (table, batch) with `watermark_value_end`.
- **The watermark is the MAX of the source's `updated_at` in the batch — not the run wall-clock
  time.** This matters: a value dated by the run time would skip any source row written while the
  run was in flight.
- Read at the start of a run (the last *succeeded* batch's `watermark_value_end`), advanced at the
  end (`complete_batch`), and — critically — **only advanced after tests pass** (see §6).

```sql
-- the current watermark per incremental table
SELECT DISTINCT ON (target_table)
       target_table, watermark_value_end
FROM audit.etl_batch_control
WHERE batch_status = 'succeeded' AND watermark_column IS NOT NULL
ORDER BY target_table, batch_end_timestamp DESC;
```

## 4. The lookback window (MED-2) — why the filter is `>` a slightly *earlier* value

A naive `updated_at > watermark` can **miss rows** at the boundary: if two rows share the exact
watermark timestamp and only one was captured before the batch cut, the other is never seen again
(it's not `>` the watermark). The extractor therefore subtracts a small **1-hour lookback**:

```
extract WHERE updated_at > (watermark − 1 hour)
```

This re-pulls a thin sliver of already-seen rows at the boundary — harmless, because silver
**hash-gates** them (§5): an unchanged re-pulled row has an identical hash and is dropped. The
lookback trades a few redundant bronze rows for a guarantee of **no missed updates**.

## 5. Hash-gating — idempotency and dedup

Every row carries a **content hash** (`bronze_row_hash` in bronze; `silver_row_hash` in silver).

- **Bronze full-load skip (FIX-016):** for `full_load` tables, a row is appended only if its hash
  isn't already the latest hash **for its natural key** (`key_columns` in the config). Comparing
  per key — not per batch — is what makes re-reading a reference table append **0** rows when
  nothing changed. (The original bug compared against the last *batch*, which is partial after a
  skip, and re-stacked the whole snapshot — see FIX-016.)
- **Silver merge gate:** silver is an incremental **merge** keyed on the business key. A row is
  updated only when its `silver_row_hash` differs from the current stored hash. So re-pulled or
  duplicate bronze rows (from the lookback, or a retried batch) collapse to a no-op.

Together these make the pipeline **idempotent**: running the same batch twice changes nothing.

## 6. Tests gate the watermark (HIGH-7)

The watermark is **not** advanced as a side effect of loading. In the Airflow DAG, `dbt test` runs
**before** `complete_gold_batches`. If a test fails, the batches stay `running`, the watermark does
**not** move, and the next run reprocesses the same window instead of skipping past bad data. A
crashed run's open batches are swept to `failed` by `fail_open_batches`, so a later manual fix can't
silently advance the watermark either.

## 7. What each tricky case does

| Case | Behavior |
|---|---|
| **Pipeline fails halfway** | Batch left `running` → swept to `failed`; watermark unmoved; rerun reprocesses the window. |
| **Same batch runs twice** | Hash-gating makes the second run a no-op (bronze skip + silver merge). |
| **A record arrives 2 days late** | Its `updated_at` is still `> watermark` on the next run → picked up normally. |
| **Source timestamp equals the watermark** | Caught by the 1-hour lookback (§4). |
| **A source row is deleted (hard delete)** | **Not** captured by timestamp CDC — a deleted row emits no `updated_at`. Known gap; the source has no soft-delete/tombstone to propagate. Reference tables catch it on the next full-load (the key disappears); transactional hard-deletes are out of scope for this source. |
| **Pipeline down for 7 days** | One catch-up run pulls everything `> watermark`; no data lost (watermark is source-time, not schedule-time). |

## 8. Where to look in the code

| Concern | Location |
|---|---|
| Table strategies + `key_columns` | `ingestion/config/ingestion_config.yml` |
| Extraction + watermark filter + lookback | `ingestion/extract/oltp_extractor.py`, `ingestion/utils/watermark.py` |
| Bronze append + full-load hash-skip | `ingestion/load/bronze_loader.py` |
| Batch open/complete/fail + watermark write | `ingestion/utils/batch_control.py` |
| Silver hash-gated merge | `dbt/printtime_dw/models/silver/*.sql` |
| Orchestration + tests-gate-watermark | `airflow/dags/printtime_elt_pipeline.py` |
