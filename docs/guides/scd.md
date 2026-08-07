# Slowly Changing Dimensions (SCD) — How It Works

How PrintTimeUSA keeps **history** in its gold dimensions: when a customer is renamed, a product is
re-priced, or an invoice's status changes, the old version is preserved and a new one opens — so
you can always ask "what did this look like **as of** a given date?"

**Related:** [ADR-015](../adr/015-gold-scd2-dbt-implementation.md) (the SCD2 pattern),
[ADR-007](../adr/007-gold-mixed-load-strategy.md) (gold load strategy),
[ADR-011](../adr/011-unknown-members-and-unenforced-fks.md) (`-1` members),
[CDC guide](cdc.md), [Governance & Audit guide](governance-and-audit.md).

---

## 1. Which SCD type, and why

SCD type is chosen **per dimension from business need**, not by default:

| Type | Meaning | Used here |
|---|---|---|
| **Type 2** | keep every version as its own row, effective-dated | the 6 dims where history matters: `dim_customer`, `dim_store`, `dim_cashier`, `dim_product`, `dim_invoice`, `dim_payment_method` |
| **Type 1 / Type 0** | overwrite / never change | small attribute-only or immutable dims (e.g. date, payment_type) |

Type 2 is only chosen where "as-was" reporting is a real requirement. Don't apply it reflexively —
it multiplies rows and complicates joins.

## 2. Anatomy of an SCD2 row

Every SCD2 dimension carries this machinery (plus its business columns):

| Column | Meaning |
|---|---|
| `source_record_id` | the durable **natural key** (e.g. the customer id) — stable across versions |
| `<dim>_key` | the **surrogate key** — a dbt-managed integer, unique per *version* row |
| `row_version` | 1, 2, 3, … per entity |
| `valid_from` / `valid_to` | the half-open effective window `[valid_from, valid_to)` |
| `is_current` | `true` on exactly one version per entity |
| `record_hash` | SHA-256 over the tracked attributes — drives change detection |
| `etl_batch_id` | which ETL run created this version (lineage → `audit.etl_batch_control`) |

Versions **tile time**: each `valid_to` equals the next version's `valid_from`, with no gaps and no
overlaps. The current version has `valid_to = NULL` (open).

## 3. The load pattern (ADR-015): append + post-hook close

The dims are dbt **incremental `append`** models with a **post-hook** that closes the prior version.
On each run:

1. **Stage** the current source rows and compute `record_hash` over the tracked attributes.
2. **Emit only changes** — a row is emitted if it's a brand-new entity, or its `record_hash`
   differs from the entity's current version. Unchanged entities emit nothing.
3. **Key & version** — each emitted row gets `row_version = current + 1` and a fresh surrogate key.
4. **Append** the new versions.
5. **Post-hook closes the old version:** `UPDATE … SET is_current = false, valid_to = <new
   version's valid_from>` where a newer `row_version` now exists.

All of this is **one transaction** with the append, so a version is never left open or double-open.

## 4. Effective dating (HIGH-3) — dated by the *business* instant, never the load date

`valid_from` comes from **`source_updated_at`** (the business change instant), **not** the load
date. This is the whole point of Type 2 — if versions were dated by when the ETL happened to run,
"as-of" reporting would be wrong.

- **The initial version (`row_version = 1`) is dated `1900-01-01`** — a low-watermark meaning
  "as far back as we know." This makes any historical fact join land on v1 by default.
- **Later versions** are dated by their `source_updated_at`.

**Facts resolve dimensions by event date**, not by `is_current`: a sale on `event_date` joins the
dimension version whose window contains it — `event_date ∈ [valid_from, valid_to)`. So a 2020 sale
always points at the 2020 version of the customer, even after four renames.

> **Why the effective date must be monotonic:** if a version's `source_updated_at` were *later* than
> a subsequent change (e.g. a backfilled test month dated before a go-live stamp), the windows would
> invert and overlap. The `assert_scd2_no_overlapping_versions` test guards exactly this.

## 5. The `-1` unknown member (ADR-011)

Every dimension has a `-1` "Not Provided" row (built once, never versioned). A failed lookup
resolves to `-1` instead of a NULL join — so unmatched facts stay **countable** rather than
vanishing.

## 6. The one correctness guard you must keep (FIX-015)

New entities arriving on an **incremental** run must resolve `current_row_version` to `0` before the
`+1`, or they get `row_version = NULL` and violate the NOT-NULL contract. Every SCD2 dim uses
`coalesce(c.row_version, 0)` for this. Verify:

```bash
grep -c "coalesce(c.row_version, 0)" dbt/printtime_dw/models/gold/dim_*.sql   # expect 1 per dim
```

## 7. Integrity tests (the SCD2 invariants)

These singular tests **gate the watermark** (a failure holds the load):

| Test | Asserts |
|---|---|
| `assert_scd2_one_current_version_per_entity` | exactly one `is_current` row per entity |
| `assert_scd2_no_overlapping_versions` | no two versions' windows overlap (monotonic effective dates) |
| contiguity check | each `valid_to` = the next `valid_from` (no gaps) |

## 8. Reading the history

```sql
-- the full version chain for one entity
SELECT source_record_id, row_version, customer_name, valid_from, valid_to, is_current, etl_batch_id
FROM   gold.dim_customer
WHERE  source_record_id = '1'
ORDER  BY row_version;

-- everything that changed in a window (a new version = a change)
SELECT source_record_id, row_version, valid_from
FROM   gold.dim_customer
WHERE  row_version > 1 AND valid_from >= DATE '2026-02-01' AND valid_from < DATE '2026-03-01';
```

A convenience function returns the change log (with old→new per column and the run that made it) for
any dim: `SELECT * FROM gold.dim_change_log('dim_store');`.

## 9. One modeling caveat (`dim_invoice`)

`dim_invoice` denormalizes `customer_name` / `store_name`, so renaming a customer mints a new
*invoice* version for each of that customer's invoices (correctly effective-dated to the invoice's
own date). It's correct but verbose — a conscious trade-off (see the audit's AUDIT-003-L1). If
invoice history should churn only on the invoice's own attributes, drop those denormalized columns
from its `record_hash`.
