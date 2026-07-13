# dbt Decisions & Changes — PrintTimeUSA DW

A running record of the dbt decisions made and changes applied while implementing the
silver layer, in the order they happened. Each entry pairs the **decision/concept** with
the **concrete artifact** in this repo that implements it, so the log doubles as an
engineering rationale and portfolio evidence.

Unlike the ADRs (`docs/adr/`), which capture major architecture decisions, this log tracks
the finer-grained, hands-on implementation choices at the dbt-model level.

**Approach:** hands-on, model-by-model. The engineer writes each model/config; the SQL
DDL in `sql/silver/` is the authoritative spec, and dbt owns table creation (see the
"dbt owns transformation" decision).

---

## Résumé-ready summary

> Built the silver layer of a medallion data warehouse in **dbt Core (PostgreSQL)**:
> authored CTE-structured transformation models, a `generate_schema_name` macro override,
> declared dbt **sources** with column-level tests, and enforced each model's DDL contract
> — data types, `NOT NULL`, and primary keys — with **dbt model contracts**, validated at
> build time. Applied deterministic **change-detection hashing** (`md5` over standardized
> business columns) to drive incremental merges, and kept batch lineage via a runtime
> `silver_batch_id` variable wired to the audit batch-control table.

---

## Lesson 1 — Macros & the `generate_schema_name` override

**Concept:** Jinja macros and dbt whitespace control (`{%- -%}`). Overriding a dbt built-in
by defining a macro of the same name.

- Wrote `macros/generate_schema_name.sql` so `+schema: silver` in `dbt_project.yml` maps to
  the literal `silver` schema (not the default `<target>_silver`).
- **Bug learned from:** deleting the `{%- else -%}` branch made the macro return an empty
  string → dbt ran `create schema if not exists ""`. Lesson: trace the macro with the
  *actual* argument value (`custom_schema_name = 'silver'`, not `none`).

**Proof in repo:** `dbt/printtime_dw/macros/generate_schema_name.sql`

## Lesson 2 — Sources & the first model

**Concept:** `sources` decouple models from raw table names; `{{ source() }}` compiles to a
real relation. A model is just one `SELECT`; dbt writes the `CREATE TABLE`.

- Declared source `bronze.ref_state` with documented columns and `not_null` tests.
- Built `models/silver/state.sql`; verified with `dbt compile` (inspect SQL) vs `dbt run`
  (build it), then confirmed the table landed in `silver.state` — proof the macro works.
- **Key lesson: compilation ≠ correctness.** `upper(trim(state_name))` compiled fine but was
  the wrong transform. dbt validates syntax, not intent.

**Proof in repo:** `dbt/printtime_dw/models/bronze/_bronze_sources.yml`, `models/silver/state.sql`

## Lesson 3 — Types & the full model (CTE pattern)

**Concept:** cast every column to its DDL type; structure models as CTEs so cleaning happens
once and derived columns reference the cleaned aliases.

- Restructured `state.sql` as `with cleaned as (...) select *, md5(...) from cleaned`.
- Three kinds of columns, three origins: **business** (cleaned from bronze), **lineage**
  (carried forward from `bronze_*`), **silver metadata** (stamped at build: `silver_batch_id`,
  `current_timestamp`).
- **Change-detection hash:** `md5(concat_ws('|', biz_col, coalesce(nullable_col,'')))` over
  the *standardized business columns only* — metadata is excluded so timestamps never look
  like a change. `coalesce` guards the `concat_ws` NULL-dropping trap.
- **Batch lineage:** `silver_batch_id` = `{{ var('silver_batch_id', -1) }}` — Airflow passes
  the real `batch_key`; `-1` marks an ad-hoc/manual run.

**Proof in repo:** `dbt/printtime_dw/models/silver/state.sql`

## Lesson 4 — Model contracts (enforcing the DDL spec)

**Concept:** a contract makes dbt build the table with real column declarations and
constraints instead of `CREATE TABLE AS SELECT`, so the database enforces the spec.

- **Why it matters:** CTAS copies column *names and types* but silently drops `NOT NULL`
  and `PRIMARY KEY`. The built table was more permissive than the DDL promised.
- Added `config: contract: enforced: true` in `_silver_models.yml`, declaring all 14 columns
  **in query order** with `data_type` + constraints (4 × `not_null`, 1 × `primary_key`).
- **Proof it flipped modes:** the run log changed from `SELECT 3` (CTAS) to `INSERT 0 3`
  (declare-then-insert). `\d silver.state` then showed `not null` on the four columns and a
  `PRIMARY KEY` index — the table finally matched the DDL.
- **Proved the guardrail bites:** a manual `INSERT` of a NULL state code and of a duplicate
  `CA` were both rejected by Postgres (`violates not-null constraint`,
  `duplicate key value ... already exists`). Before the contract, both would have succeeded.
- **Gotchas:** contract lists columns in the order the *query* emits (so `silver_row_hash`,
  added by `select *, md5(...)`, is last — not the DDL's order). The PK auto-named
  `state__dbt_tmp_pkey` from dbt's temp-table build; cosmetic, works fine.

**Proof in repo:** `dbt/printtime_dw/models/silver/_silver_models.yml`

## Lesson 5 — Deduplication with `ROW_NUMBER()`

**Concept:** bronze is append-only (ADR-004), so one business key can have many bronze rows.
Silver keeps exactly one current row per key (ADR-006 step 2), collapsed with a window
function.

- Added a `deduped` CTE ahead of `cleaned`: `row_number() over (partition by <business key>
  order by <freshness>)`, then `where rn = 1`.
- **Freshness order is the project standard** (`silver_incremental_merge_strategy.md`), the
  same for every table: `updated_at_source_timestamp desc nulls last, created_at_source_timestamp
  desc nulls last, bronze_loaded_at_timestamp desc, bronze_record_id desc`. The final
  `bronze_record_id` (monotonic) guarantees a deterministic winner — no random ties.
- **Decision corrected against spec:** an earlier draft ordered product by `source_row_version`;
  the documented rule standardizes on `updated_at_source_timestamp` (present on every table),
  so the spec won. Rule of thumb reaffirmed: **the project spec is the source of truth.**
- `partition by` uses the **raw bronze key** (`product_id`), not the silver alias — the window
  runs before the `cleaned` rename.
- Applied to `state.sql` (defensively — a reload could dup) and `product.sql`.

**Proved end-to-end (not just asserted):** injected 3 updated copies of products 1–3 into
`bronze.oltp_product` (new `bronze_record_id`, later `updated_at`, prices 888.88/999.99,
test batch 999999) → bronze 1003 rows / 1000 keys. Re-ran `product`:
- silver stayed **1000 rows / 1000 keys** — duplicates collapsed;
- products 1–3 showed the **new** prices + **new** hashes — the latest version won;
- `INSERT 0 1000` held — the PK contract would have rejected a broken dedup (two rows/key).
Then deleted batch 999999 and rebuilt to restore true seeded values.

**Why dedup matters even on clean data:** it is a no-op today (one load, no dupes) but the
next incremental append *will* create dupes; without it, the second load violates the PK
contract. Dedup upgrades a model from works-once to works-always.

**Proof in repo:** `dbt/printtime_dw/models/silver/state.sql`, `product.sql`

## Lesson 6 — Incremental materialization (the real ADR-006 merge)

**Concept:** `materialized: table` fully rebuilds every run — correct rows, but it resets
`silver_created_at_timestamp`/`silver_updated_at_timestamp` on every row every time, so the
temporal metadata lies (ADR-006 rejected this as alternative #2). `materialized: incremental`
builds once, then processes only new/changed rows.

Converted `state.sql` with a `config()` block:

```sql
{{ config(
    materialized='incremental',
    unique_key='silver_state_code',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}
```

- **Watermark (ADR-006 step 1)** — an `{% if is_incremental() %}` block filters the source:
  `where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})`.
  `{{ this }}` is the model's own table; `is_incremental()` is false on the first run / on
  `--full-refresh` (so the filter vanishes and it full-builds), true thereafter.
- **Merge (step 3)** — `unique_key` + `incremental_strategy='merge'` compile to
  `INSERT ... ON CONFLICT (silver_state_code) DO UPDATE`: new keys insert, existing keys
  update. The **contract PK is what makes `ON CONFLICT` work** — contracts + incremental pair
  by design.
- **Two timestamps (step 4)** — `merge_exclude_columns=['silver_created_at_timestamp']`
  keeps `created` frozen on update while everything else (incl. `updated`) refreshes.
- **Contract quirk learned from the error:** incremental + contract forbids the default
  `on_schema_change='ignore'`; must be `'fail'` or `'append_new_columns'`. Chose `fail` —
  the DDL contract fixes the schema, so any drift should be a loud error.

**Proved (state, live):** full-refresh built at batch 60 (`incremental model`, both ts equal).
Injected an updated CA at batch 999999, ran without `--full-refresh` → log showed `MERGE 1`;
CA name changed, `created` stayed 23:41:46, `updated` advanced to 23:44:00; AZ/TX **frozen**
(watermark excluded them, batch 1 not > 1).

## Lesson 6b — The hash gate (only update on genuine change)

**Concept:** the watermark lets through every row in a new batch, including re-extracts whose
data didn't change. Merging those would falsely bump `silver_updated_at_timestamp` — breaking
the signal gold uses for SCD2 (ADR-007). ADR-006 step 3 requires updating only when
`silver_row_hash IS DISTINCT FROM` the stored hash.

Implemented as a filter in the final select (contract-safe: still `select f.*` = the declared
columns; the joined table is only used for filtering):

```sql
select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_state_code = f.silver_state_code
where existing.silver_state_code is null                          -- new key  -> insert
   or existing.silver_row_hash is distinct from f.silver_row_hash -- changed  -> update
{% endif %}
```

- `IS DISTINCT FROM`, not `<>` — NULL-safe (`<>` returns NULL against NULLs and silently drops
  rows).
- Watermark and hash gate are complementary: watermark = "only new batches" (coarse,
  efficient); hash gate = "only genuinely-changed rows" (fine).

**Proved (state, live, two-part):**
- **Identical re-load** (same business data, new batch 999999) → `MERGE 0`; CA `updated_at`
  stayed frozen. No-op, exactly as intended.
- **Genuine change** (new name) → `MERGE 1`; `updated_at` advanced, `created_at` preserved,
  AZ/TX untouched. Same watermark, opposite outcome — decided solely by the hash.

`silver.state` is now the complete ADR-006 reference model: watermark + dedup + hash-gated
merge + honest timestamps + enforced contract.

**Proof in repo:** `dbt/printtime_dw/models/silver/state.sql`

---

## Concept quick-reference

| Concept | One-liner | Where |
|---|---|---|
| Macro override | same-name macro replaces a dbt built-in | Lesson 1 |
| Whitespace control | `{%- -%}` trims render whitespace | Lesson 1 |
| Sources | `{{ source() }}` → real relation, decoupled | Lesson 2 |
| `compile` vs `run` | inspect SQL vs build the table | Lesson 2 |
| CTE pattern | clean once, derive from aliases | Lesson 3 |
| Casting | match column to DDL type (`::varchar(2)`) | Lesson 3 |
| Change-detection hash | `md5` over business cols only | Lesson 3 |
| dbt vars | `{{ var('x', default) }}` runtime value | Lesson 3 |
| Model contract | build-time enforcement of types + constraints | Lesson 4 |
| CTAS vs declare-then-insert | `SELECT n` vs `INSERT 0 n` in the log | Lesson 4 |
| Deduplication | `ROW_NUMBER()` + `where rn = 1` → one current row/key | Lesson 5 |
| Deterministic freshness order | tie-break on monotonic `bronze_record_id` | Lesson 5 |
| Incremental materialization | build once, then process only new/changed rows | Lesson 6 |
| `is_incremental()` + `{{ this }}` | watermark: read model's own table for max batch | Lesson 6 |
| `merge` + `unique_key` | `ON CONFLICT DO UPDATE`; insert new, update existing | Lesson 6 |
| `merge_exclude_columns` | preserve `created` on update; advance `updated` | Lesson 6 |
| `on_schema_change='fail'` | required by incremental + contract; loud on drift | Lesson 6 |
| Hash gate | `IS DISTINCT FROM` in final select → update only on real change | Lesson 6b |

---

## Next up

- **Apply incremental to `product`** — copy the `state` template: config block
  (`unique_key='silver_product_id'`), watermark, and hash gate (join on
  `silver_product_id`).
- **Data tests** — `unique`/`not_null` as dbt tests alongside the contract constraints.
- **Remaining 18 silver models** — apply the established pattern.
