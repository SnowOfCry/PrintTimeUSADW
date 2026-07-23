# Gold Load Strategy

PrintTimeUSA Data Warehouse | Gold dimensional layer.

## Why Gold mixes strategies

Bronze and Silver each use one strategy for every table (append-only, incremental merge). Gold cannot, because its tables do different jobs:

- **Dimensions** describe entities whose attributes change over time — most of them must *rebuild curated history* (SCD Type 2) from Silver's current-clean rows.
- **Facts** record measurements at a fixed grain — they are *immutable once correct* and are appended, snapshotted, or reloaded at their parent grain, never versioned.

The medallion arc across the three layers:

| Layer | Strategy | Keeps |
|---|---|---|
| Bronze | incremental_append | Every raw source-row version (immutable history) |
| Silver | incremental_merge | One clean, current row per business key |
| Gold | mixed (this doc) | Curated history (SCD2 dims) + immutable measurements (facts) |

## How each table's strategy was chosen

Two signals from the Gold specs decide the strategy per table:

1. **Does the table carry the SCD2 block** (`valid_from`, `valid_to`, `is_current`, `row_version`) in `sql/gold/002_create_gold_tables.sql` and the gold data dictionary? If yes, the design intends Type 2 history. If deliberately absent (`dim_payment_type`, `dim_date`, all facts), the design intends overwrite, generation, or append.
2. **What is the table's grain** per the Silver-to-Gold mapping? The grain determines the natural reload unit for facts.

## Dimension load strategies

| Dimension | Strategy | Justification |
|---|---|---|
| gold.dim_date | Type 0 — generate once, extend forward | Static calendar; no SCD2 columns; `date_key` (YYYYMMDD) is deterministic. Never updated, only extended. |
| gold.dim_payment_type | Type 1 — upsert on `type_code` | Static lookup (DEPOSIT/BALANCE/FULL/REFUND/ADJUSTMENT); the DDL deliberately omits the SCD2 block; history is irrelevant. Overwrite in place. |
| gold.dim_payment_method | Type 2 | Carries the SCD2 block. Low churn, but method reclassification (type/active) is worth tracking. |
| gold.dim_product | Type 2 | Carries the SCD2 block. Price/markup/category changes must be point-in-time correct for margin analysis. |
| gold.dim_store | Type 2 | Carries the SCD2 block. Region/type/name changes need trend continuity. |
| gold.dim_cashier | Type 2 | Carries the SCD2 block. Store reassignment and active-status changes need history. |
| gold.dim_customer | Type 2 | Carries the SCD2 block. Address, status, and city/state change over time. |
| gold.dim_invoice | Type 2 (standard, status/total driven) | Carries the SCD2 block, built as a **standard Type 2** from `silver.invoice` (matched on the durable `silver_invoice_id`). Fidelity is bounded by gold run frequency (see caveat below); a daily run captures the days-to-weeks OPEN → PARTIAL → PAID → VOID lifecycle in practice. `silver.invoice_status_history` is **not** used to build dim versions (it can't reconstruct historical totals) — it remains the authoritative status-transition record for exact status-duration analysis, used directly or via a future invoice-status snapshot fact (backlog). |

### How SCD2 works here

**Natural key = the durable source id, not a display code.** Each Type 2 load matches the incoming Silver row to the dimension's **current** version (`is_current = TRUE`) on `source_record_id` — the durable source primary id (`silver_product_id`, `silver_customer_id`, …), **not** a mutable attribute like `sku_number` or `store_code`. Matching on a mutable code would orphan history the moment the code is corrected; matching on the durable id means a code change simply produces a new *version* (which is correct). Change within a version is detected with `record_hash` (SHA-256 of the tracked attributes).

1. **New key** — insert version 1: `valid_from = load date`, `valid_to = NULL` (open), `is_current = TRUE`, `row_version = 1`.
2. **Hash unchanged** — do nothing (no churn).
3. **Hash changed** — insert the new version (`row_version + 1`, `is_current = TRUE`), then close the prior version (`valid_to = load date`, `is_current = FALSE`).

```sql
-- change detection sketch (match on the durable source id)
UPDATE gold.dim_product d
SET    valid_to = CURRENT_DATE, is_current = FALSE, etl_updated_timestamp = CURRENT_TIMESTAMP
FROM   staged s
WHERE  d.source_record_id = s.source_record_id
  AND  d.is_current
  AND  d.record_hash IS DISTINCT FROM s.record_hash;
-- then INSERT the new versions (row_version = old + 1)
```

**dbt implementation (ADR-015).** Each Type 2 dim is a **custom incremental model** with `incremental_strategy='append'`: it inserts only new/changed versions (new `source_record_id`, or `record_hash` changed vs. the current version), then a **post-hook** closes any superseded version (`is_current=FALSE`, `valid_to=CURRENT_DATE`). Append (not merge) is essential — merge would overwrite the prior row in place, collapsing Type 2 into Type 1. Surrogate keys (dbt-managed plain `INTEGER`s — decision #7) are therefore stable across runs, which is what lets facts reference them. dbt's built-in `snapshot` was rejected: its fixed `dbt_valid_*` columns don't match this DDL (`valid_from/to`, `is_current`, `row_version`, the dbt-managed surrogate key, DQ columns), and it would still need an incremental reshaping model on top. See ADR-015.

**Fidelity caveat:** Silver keeps only the current version per key, so Gold can only version what it sees between runs. If an attribute changes twice between two Gold runs, the intermediate state is collapsed into one new version. This is acceptable for slow-moving dimensions, invoices included (a daily run captures the days-to-weeks status lifecycle). Where exact status-transition timing is required, `silver.invoice_status_history` / `customer_status_history` preserve the full event timeline (with `changed_at`) and are queried directly for status-duration analysis — they are not used to rebuild dimension versions, since Silver retains only current financial totals and cannot reconstruct point-in-time amounts for past transitions.

## Fact load strategies

Facts carry no SCD2 block by design. Each fact reloads at its natural parent grain — the unit at which the source actually changes.

**Change detection (incremental).** Gold detects what changed via `silver_updated_at_timestamp` compared against the last successful gold batch recorded in `audit.etl_batch_control` for that target table. Because silver advances `silver_updated_at_timestamp` only on a genuine change (the hash-gated merge, ADR-006), this timestamp is a reliable change signal — gold reloads only the invoices/payments touched since its last run, not the whole table. (Full reload remains an acceptable fallback at current volumes per ADR-007, but incremental is the default.)

| Fact | Grain | Strategy |
|---|---|---|
| gold.fact_retail_sales | one row per invoice line | **Incremental reload-by-invoice**: for each invoice whose header (`silver.invoice`) or any line (`silver.invoice_line`) has `silver_updated_at_timestamp` > last gold batch, `DELETE WHERE invoice_number = :n` and reinsert its lines from `silver.invoice_line`. |
| gold.fact_payments | one row per payment | **Incremental insert + second pass**: reload payments whose `silver_updated_at_timestamp` > last gold batch (per invoice via `invoice_key`), then a second pass resolves the self-referencing `parent_payment_key`. |
| gold.fact_customer_behavior_snapshot | one row per customer per snapshot date | **Periodic snapshot, append-only — monthly (month-end)**: on the month-end run, insert the full customer population for that `snapshot_date_key` (~10k rows/month, ~120k/year). Other daily runs do not append. Prior snapshots are immutable history and are never updated. |

### Why the facts carry no source business keys (design decisions)

These were explicit decisions, validated against the seeded OLTP data:

- **`fact_retail_sales` needs no `invoice_line_id` / `line_number`.** `invoice_number` is the genuine OLTP invoice number carried as a degenerate dimension. Because the reload unit is the whole invoice, the ETL never needs to identify a single line — deleting and reinserting the invoice's lines covers inserts, edits, and voids. `line_number` would only earn a place for line-item drill-through reporting, not for loading.
- **`fact_payments` needs no `payment_id`.** In the source data, `(invoice_id, payment_sequence)` is unique across all 57,409 payments (≈39% of invoices have 2–3 payments: deposit, balance, occasional refund). The fact already carries `payment_sequence_num`, so `(invoice_key, payment_sequence_num)` uniquely identifies any payment row for matching or surgical updates.
- **The refund chain resolves without `payment_id`.** `parent_payment_key` is built at load time from `silver.payment`, which retains both `payment_id` and `parent_payment_id`: refund → parent's `(invoice_id, payment_sequence)` → parent's `payment_key` in the fact. The source id is needed only during the load, never persisted on the fact.

```sql
-- fact_payments second pass: resolve refunds -> original payments
UPDATE gold.fact_payments f
SET    parent_payment_key = p.payment_key
FROM   silver.payment s              -- refund row (has silver_parent_payment_id)
JOIN   silver.payment sp  ON sp.silver_payment_id = s.silver_parent_payment_id
JOIN   gold.dim_invoice di ON di.invoice_number = (SELECT silver_invoice_number FROM silver.invoice i WHERE i.silver_invoice_id = sp.silver_invoice_id) AND di.is_current
JOIN   gold.fact_payments p ON p.invoice_key = di.invoice_key
                           AND p.payment_sequence_num = sp.silver_payment_sequence_num
WHERE  f.invoice_key = (SELECT invoice_key FROM gold.dim_invoice d2 WHERE d2.invoice_number = (SELECT silver_invoice_number FROM silver.invoice i2 WHERE i2.silver_invoice_id = s.silver_invoice_id) AND d2.is_current)
  AND  f.payment_sequence_num = s.silver_payment_sequence_num
  AND  s.silver_parent_payment_id IS NOT NULL;
```

(Sketch — the production version stages the key resolution instead of nesting subqueries.)

## Not Provided members

Every dimension is seeded with a `-1` "Not Provided" member (`customer_key = -1`, attributes `'Not Provided'`, ADR-011). Any fact row whose dimension lookup fails resolves to `-1` instead of NULL, so BI tools never produce blank-row joins and unmatched rows stay countable.

**Seeding mechanism.** The `-1` member has no Silver source row, so it is a **literal row in the model** — `UNION ALL select -1, 'Not Provided', …` — that flows through the same append/merge as the real rows. Because surrogate keys are dbt-managed integers (ADR-015 / decision #7), the model simply emits `-1`; no DB-identity override or post-hook is needed. Real rows get positive keys (`1, 2, 3, …`) that never collide with `-1`.

## Load order

Dimensions load before facts because facts resolve dimension surrogate keys by lookup; `dim_date` loads first because everything date-keyed depends on it.

```
1. gold.dim_date                      (generate / extend)
2. Seed -1 Not Provided member in every dimension (first run only)
3. gold.dim_payment_type              (Type 1)
4. gold.dim_payment_method            (Type 2)
5. gold.dim_product                   (Type 2)
6. gold.dim_store                     (Type 2)
7. gold.dim_cashier                   (Type 2)
8. gold.dim_customer                  (Type 2; needs dim_date for first_order_date_key)
9. gold.dim_invoice                   (Type 2)
10. gold.fact_retail_sales            (reload-by-invoice)
11. gold.fact_payments — pass 1       (insert rows)
12. gold.fact_payments — pass 2       (resolve parent_payment_key)
13. gold.fact_customer_behavior_snapshot (append new snapshot date)
```

Fact-to-dimension lookups use the **current** dimension version (`is_current = TRUE`) at load time; an as-of (effective-dated) join on `valid_from`/`valid_to` may be substituted where point-in-time key assignment is required.

## Batch control

Every Gold table load runs as a batch in `audit.etl_batch_control`, exactly like Bronze: one row per target table per run with `load_type` (`scd2_merge`, `type1_upsert`, `fact_reload`, `snapshot_append`, `generate`), row counts, status, and timestamps. Gold reads Silver directly (it does not re-derive from Bronze, so no bronze-batch watermark applies). Instead, Gold's incremental change detection uses `silver_updated_at_timestamp` versus the **last successful Gold batch timestamp** for that target table in `audit.etl_batch_control` — that batch timestamp is Gold's watermark. Dimensions additionally gate on `record_hash` (SCD2); the snapshot fact is append-only by `snapshot_date_key`.
