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

---

## Next up

- **Deduplication** with `ROW_NUMBER()` — collapse bronze's append-only history to one
  current row per business key (needed for `customer`, `product`, etc.).
- **Incremental materialization** — turn full-rebuild models into the `incremental_merge`
  the load strategy specifies.
- **Data tests** — `unique`/`not_null` as dbt tests alongside the contract constraints.
