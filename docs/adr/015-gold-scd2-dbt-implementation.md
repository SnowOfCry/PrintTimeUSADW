# ADR-015: Gold SCD2 Dimensions — Custom Incremental dbt Model (append + post-hooks) over dbt Snapshots

- **Status:** Accepted
- **Date:** 2026-07-17
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

ADR-007 chose SCD Type 2 for six gold dimensions (`dim_payment_method`, `dim_product`, `dim_store`, `dim_cashier`, `dim_customer`, `dim_invoice`) and `gold_load_strategy.md` describes the mechanics (compare to the current version by `record_hash`; close the old version; insert the new one). What neither fixed is **how SCD2 is implemented in dbt** — a real decision, because dbt offers a first-class SCD2 feature (`snapshot`) that does not match this project's bespoke gold DDL.

Two hard constraints frame the choice:

1. **Surrogate keys must be stable across runs.** Facts join to `product_key = 42`; if any run regenerated that key, every fact would silently point at the wrong entity. So a dimension can never be full-rebuilt — it must *append* new versions and preserve existing keys.
2. **The gold DDL is bespoke.** Each dim carries `valid_from`, `valid_to`, `is_current`, `row_version`, an identity surrogate key, `record_hash` (SHA-256), DQ columns (`is_complete`, `is_validated`, `dq_issue_flag`, …), soft-delete columns, and a seeded `-1` "Not Provided" member (ADR-011).

## Decision

**Build each Type 2 dimension as a custom incremental dbt model** with `incremental_strategy='append'` plus post-hooks, matching the gold DDL exactly.

- **Match on the durable source id.** SCD2 compares the incoming silver row to the dimension's current version (`is_current = TRUE`) on **`source_record_id`** (the durable source primary id — `silver_product_id`, `silver_customer_id`, …), **not** a mutable display code (`sku_number`, `store_code`). A code change then correctly produces a new *version*, never an orphaned entity.
- **Append, not merge.** A changed entity gets a **new version row** inserted (`row_version + 1`, `is_current = TRUE`, `valid_from = CURRENT_DATE`, `valid_to = NULL`); the prior row is untouched by the insert. Merge (upsert) would overwrite the prior row in place — collapsing Type 2 into Type 1 and destroying history.
- **Post-hook — close superseded versions.** After the append, `UPDATE {{ this }} SET is_current = FALSE, valid_to = CURRENT_DATE WHERE is_current AND a higher row_version now exists for that source_record_id`.
- **Change within a version** is detected by `record_hash IS DISTINCT FROM` the current version's hash, computed over the tracked attributes only (same principle as the silver hash gate, ADR-006).

### Surrogate keys are dbt-managed integers, not a DB identity (decision #7)

dbt owns gold table creation (as it does for silver), and dbt's model contract has no
"identity" concept and requires the model to produce every contracted column — so a
`GENERATED … AS IDENTITY` column (which the *database* fills) does not fit. Therefore **the
model generates the surrogate key**, as a plain `INTEGER`: on a full build, `row_number()`;
on incremental runs, existing keys are **preserved** by reading them from `{{ this }}` (join on
the durable natural key) and new rows get `max(existing key) + a running count of new rows`.
This keeps keys stable across runs (facts can reference them) exactly as an identity would — the
stability comes from the append-only design plus preserving existing keys, not from the DB.

Consequently the gold DDL surrogate keys are plain `INTEGER` (the `GENERATED … AS IDENTITY`
clause was removed from `sql/gold/002`), and **the `-1` "Not Provided" member is a literal row
in the model** (`UNION ALL select -1, 'Not Provided', …`) that flows through the same
merge/append — no post-hook and no `OVERRIDING SYSTEM VALUE` are needed. Verified on
`dim_payment_type`: keys stayed identical across a second incremental run.

The pattern is written once and repeated across the six Type 2 dims (a strong macro candidate). `dim_date` (Type 0) and `dim_payment_type` (Type 1) do not use it.

## Alternatives considered

1. **dbt `snapshot` (built-in SCD2) + a reshaping model.** dbt's tested SCD2 engine, rejected as the primary approach: snapshots emit fixed `dbt_valid_from`/`dbt_valid_to`/`dbt_scd_id` columns that do not match this DDL (`valid_from/to`, `is_current`, `row_version`, identity key, DQ columns, `-1` member), so a second model would be needed to rename, compute `row_version`, add the surrogate key, and seed `-1` — and that second model must *also* be incremental to keep keys stable. The result is more moving parts and a column mismatch, with the engine's advantage largely cancelled. Kept in mind as a fallback if the custom pattern ever proves fragile.
2. **Full-rebuild the dimension each run (Type 1-style truncate + insert history).** Rejected outright: regenerates surrogate keys every run, breaking every fact reference — violates constraint #1.
3. **`incremental_strategy='merge'` on the natural key.** Rejected: merge overwrites the current row, which is Type 1. It cannot keep prior versions, so it cannot do SCD2.
4. **Database identity surrogate keys (`GENERATED … AS IDENTITY`).** The original DDL used them, rejected because dbt owns table creation and its contract can neither express "identity" nor let the model omit a contracted column — the DB-generated value has nowhere to come from. dbt-managed integer keys (decision #7 above) replace them; the `-1` member becomes a literal model row rather than an `OVERRIDING SYSTEM VALUE` insert.

## Consequences

**Positive**

- The dbt models produce the gold DDL exactly — versions, `row_version`, stable dbt-managed integer keys, `record_hash`, DQ columns, and the `-1` member — with the whole SCD2 logic owned and visible in one file per dim.
- Surrogate keys are stable across runs, so facts can safely reference them.
- Incremental by construction: only new/changed versions are written; unchanged entities cost nothing (append writes zero rows, the close post-hook matches none).
- The pattern is uniform across the six Type 2 dims — factorable into a macro, and interview-defensible ("we hand-rolled SCD2 to match a bespoke Kimball DDL, and here's why not snapshots").

**Negative / accepted costs**

- More hand-written SQL than `snapshot`, and the correctness of "append new + close old" lives in the model + post-hook rather than a dbt built-in — so it must be tested carefully (unique current-version-per-key, monotonic `row_version`).
- `GENERATED BY DEFAULT` permits explicit key inserts; safe here, but a convention to document (only the `-1` seed inserts an explicit key).
- Fidelity is bounded by gold run frequency (ADR-007 / gold load strategy): an attribute that changes twice between runs yields one new version. Accepted for slow-moving dimensions.

## Related

- ADR-007 (gold load strategy — which dims are Type 2), ADR-006 (silver hash-gated merge — the change-signal reused here), ADR-011 (`-1` Not Provided members)
- `docs/load_strategy/gold_load_strategy.md` — the per-table mechanics and load order
- `sql/gold/002_create_gold_tables.sql` — the dimension DDL (identity keys now `GENERATED BY DEFAULT`)
