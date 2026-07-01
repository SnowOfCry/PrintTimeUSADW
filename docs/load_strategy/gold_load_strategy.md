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
| gold.dim_invoice | Type 2 (status/total driven) | Carries the SCD2 block. The OPEN → PARTIAL → PAID → VOID lifecycle is a core business requirement; `silver.invoice_status_history` supplies the authoritative transition timeline. |

### How SCD2 works here

Each Type 2 load compares the incoming Silver row against the dimension's **current** version (`is_current = TRUE`) for that natural key using `record_hash` (SHA-256 of tracked attributes):

1. **New key** — insert version 1: `valid_from = load date`, `valid_to = NULL` (open), `is_current = TRUE`, `row_version = 1`.
2. **Hash unchanged** — do nothing (no churn).
3. **Hash changed** — close the current version (`valid_to = load date`, `is_current = FALSE`), then insert the new version with `row_version + 1`.

```sql
-- change detection sketch
UPDATE gold.dim_product d
SET    valid_to = CURRENT_DATE, is_current = FALSE, etl_updated_timestamp = CURRENT_TIMESTAMP
FROM   staged s
WHERE  d.sku_number = s.sku_number
  AND  d.is_current
  AND  d.record_hash IS DISTINCT FROM s.record_hash;
-- then INSERT the new versions (row_version = old + 1)
```

**Fidelity caveat:** Silver keeps only the current version per key, so Gold can only version what it sees between runs. If an attribute changes twice between two Gold runs, the intermediate state is collapsed into one new version. This is acceptable for slow-moving dimensions; for the one case where every transition matters — invoice status — `silver.invoice_status_history` (and `customer_status_history` for customer status) preserves the full timeline and can rebuild `dim_invoice` versions exactly.

## Fact load strategies

Facts carry no SCD2 block by design. Each fact reloads at its natural parent grain — the unit at which the source actually changes.

| Fact | Grain | Strategy |
|---|---|---|
| gold.fact_retail_sales | one row per invoice line | **Reload-by-invoice**: for each new/changed invoice, `DELETE WHERE invoice_number = :n`, reinsert its lines from `silver.invoice_line`. |
| gold.fact_payments | one row per payment | **Incremental insert + second pass**: insert new/changed payments (reload per invoice via `invoice_key`), then a second pass resolves the self-referencing `parent_payment_key`. |
| gold.fact_customer_behavior_snapshot | one row per customer per snapshot date | **Periodic snapshot, append-only**: each run inserts the full customer population for the new `snapshot_date_key`. Prior snapshots are immutable history and are never updated. |

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

## Unknown members

Before the first fact load, every dimension is seeded with a `-1` "Unknown" member (`customer_key = -1`, attributes `'Unknown'`). Any fact row whose dimension lookup fails resolves to `-1` instead of NULL, so BI tools never produce blank-row joins and unmatched rows stay countable.

## Load order

Dimensions load before facts because facts resolve dimension surrogate keys by lookup; `dim_date` loads first because everything date-keyed depends on it.

```
1. gold.dim_date                      (generate / extend)
2. Seed -1 Unknown member in every dimension (first run only)
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

Every Gold table load runs as a batch in `audit.etl_batch_control`, exactly like Bronze: one row per target table per run with `load_type` (`scd2_merge`, `type1_upsert`, `fact_reload`, `snapshot_append`, `generate`), row counts, status, and timestamps. Gold loads read Silver directly (no watermark needed — Silver is already current), so `watermark_column`/`watermark_value_*` stay NULL for Gold batches.
