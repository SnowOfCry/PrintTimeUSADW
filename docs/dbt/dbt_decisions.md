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

## Lesson 7 — Normalization, controlled vocabularies, and derived columns (silver.customer)

**Concept:** the first model beyond pure cast-and-clean. `customer` applies the three ADR-005
standards that `state`/`product` didn't need: field normalization, controlled vocabularies,
and derived business columns. Same incremental/contract machinery as before.

**1. Field normalization** — make equal values become identical strings so the hash only
changes on real change (and gold doesn't get phantom SCD2 versions):
- **Collapse internal spaces** (distinct from dedup's "collapse rows"): `trim` removes only end
  whitespace; `regexp_replace(x, '\s+', ' ', 'g')` squeezes internal runs to one space, so
  `"Elite   Roofing"` and `"Elite Roofing"` hash the same.
- **Person names** — Title Case: `initcap(nullif(regexp_replace(trim(x), '\s+', ' ', 'g'), ''))`.
- **Business names** — same clean but **no `initcap`** (preserve case: `PepsiCo`, `LLC`, `AA`).
- **Email** — `lower`: `nullif(trim(lower(email)), '')`.
- **Phone** — strip non-digits: `nullif(regexp_replace(phone, '[^0-9]', '', 'g'), '')`. Decision:
  keep whatever digits remain even if not 10 (non-destructive; silver keeps everything with
  business meaning). All 10,000 rows stripped cleanly to 10 digits.

**2. Controlled vocabulary (ADR-005 #4)** — write the closed set explicitly so junk can't leak:
```sql
case lower(trim(customer_status))
    when 'active'   then 'active'
    when 'inactive' then 'inactive'
    else null                      -- outside the closed set
end::varchar(20) as silver_customer_status
```
A bare `lower()` would pass any value through; the `case` enforces `{active, inactive, null}`.

**3. Derived columns (ADR-005 #5)** — columns with no direct bronze source:
- `silver_is_active_flag` — boolean expression: `(lower(trim(customer_status)) = 'active')::boolean`.
- `silver_customer_name` — one `case`, two branches, **different casing per branch**:
  business name if present (case preserved), else Title-Cased `concat_ws(' ', first, last)`.

**Decision — customer_name rule kept as spec (business, else person).** The user proposed
reversing to person-first; the data showed all 10,000 rows have a person name and 6,977 also
have a business name, so person-first would make business_name never used and show every B2B
customer as its contact person. Rejected — kept ADR-005 (business, else person). Reaffirms:
spec is the source of truth; a change would have required updating ADR-005 + the validation doc.

`full_name` in bronze is 100% empty, so `silver_customer_name` is built from first+last, not
mapped from `full_name` — a decision driven by inspecting the data, not the mapping doc.

**Proved (live):** built 10,000 rows; 6,977 customer_names from business / 3,023 from person
(matches the split); 0 statuses outside the vocabulary; 0 phones not 10 digits; 8,271
`is_active_flag = true` (matches the 8,271 ACTIVE rows). Contract enforced (4 NOT NULLs + PK).

**Proof in repo:** `dbt/printtime_dw/models/silver/customer.sql`

## Lesson 8 — Completing the layer: transactional, history-tracked, and derived flags

**Concept:** the remaining 17 models reuse the established template; three patterns were new.

**1. History-tracked tables (ADR-006 exception)** — `invoice_status_history`,
`customer_status_history` keep **one row per transition, never collapsed to "current"**
(the timeline itself is the business record, feeding gold SCD2 / behavior snapshot). Adaptations:
- business key is `status_history_id` (each transition its own row); dedup only guards against
  re-extracts of the same transition.
- the source is insert-only and has **no created/updated timestamps — only `changed_at`** — so
  the freshness order and `silver_source_created/updated` both use `changed_at`.
- `old_status`/`new_status` use the lowercase status vocabulary; `old_status` is legitimately
  NULL on the first ("invoice created") transition.

**2. Derived business flags with a fixed formula (ADR-005 #5)** — `silver.invoice` computes
two flags from the **raw** amount columns (can't reference silver aliases in the same SELECT):
- `silver_has_balance_due_flag = balance_due_amount > 0`
- `silver_paid_in_full_flag = paid_amount >= total_amount`

**Decision — `paid_in_full` uses `paid_amount >= total_amount`, not `balance_due_amount <= 0`.**
The two differ only on VOID: a voided invoice closes with `balance <= 0` but `paid < total`, so
`balance <= 0` would wrongly flag all 2,396 voids as "paid in full". `paid >= total` excludes
them. Verified against all 59,950 invoices (paid → true; open/partial/void → false). ADR-005 #5
named these flags but not their formulas; the formulas are now pinned in ADR-005's
"Derived flag definitions" table, closing the "named but undefined" gap the spec-first skill
exists to catch.

**3. The dw-spec-first skill** — added `.claude/skills/dw-spec-first`, which requires reading
the governing spec (ADR / DDL / dictionary / mapping / validation set) before writing, and makes
the spec win over intuition. It caught a real violation on first use: `invoice_status` had been
built with source-case codes (`OPEN`), violating ADR-005 #4's lowercase-vocabulary rule; fixed
to `open/partial/paid/void`. Also drove a contract audit that found 3 NOT NULLs
(`silver_created_at_timestamp`, `silver_updated_at_timestamp`, `silver_is_deleted_flag`) missing
from every contract vs the DDL — added across all models, so every silver table now enforces its
full 7 NOT NULLs.

**Silver layer complete: 20/20 models, `dbt build --select silver` = PASS 20.**

**Proof in repo:** `dbt/printtime_dw/models/silver/` (all 20), `.claude/skills/dw-spec-first/`

## Lesson 9 — The gold layer: SCD2 dimensions, facts, and the star schema

**Concept:** gold is where dbt stops producing "one clean row per key" and starts producing a
Kimball star schema — surrogate keys, versioned history, fact grain, and `-1` members. Seven
design decisions were locked *before* writing any model (recorded in `gold_load_strategy.md`
and ADR-015), and the whole layer was built one object at a time with a live verification per
object: 14 objects, `dbt build --select gold` = PASS 64.

**1. Decisions before code (the spec-first payoff).** Reviewing the gold load strategy against
the DDL and the real data surfaced six open questions + one that emerged during the build:
match SCD2 on the durable `source_record_id`, not display codes (#1); `dim_invoice` is standard
Type 2, not rebuilt from status history (#2); facts are incremental via
`silver_updated_at_timestamp` vs. the last gold batch (#3); monthly month-end snapshots (#4);
`-1` members (#5, later simplified by #7); custom incremental SCD2 over dbt snapshots (#6,
ADR-015); and **dbt-managed integer surrogate keys** instead of DB identity columns (#7 — a
contract can neither express `GENERATED AS IDENTITY` nor let the model omit the column).

**2. The SCD2 pattern (ADR-015)** — one shape reused across all six Type 2 dims:
- `incremental` + **`append`** (merge would overwrite in place = Type 1);
- `staged` computes a SHA-256 `record_hash` over tracked attributes (needs `pgcrypto`, now in
  the DB init); `changed` emits only new entities or changed hashes vs. `{{ this }}` current;
- each emitted row is a **new version** (`row_version + 1`, fresh key = max + offset,
  `is_current = true`); a **post-hook** closes the superseded version
  (`is_current = false`, `valid_to = current_date`);
- the `-1` member is a literal `UNION ALL` row emitted **only on the first build**
  (`{% if not is_incremental() %}`), so the append never duplicates it.
Every dim passed the same live proof: no change → `INSERT 0 0`; a real change → exactly one new
version with the old key preserved; 0 entities with more than one current version.

**3. Facts are lookups + grain, not versions.** Dimension keys resolve against the *current*
version on the durable id, `coalesce(..., -1)`; measures are cast to the DDL; the surrogate key
continues from `max({{ this }})`. Per-fact strategies: `fact_retail_sales` uses
`delete+insert` keyed on `invoice_number` (reload-by-invoice, ADR-009 — no line id needed);
`fact_payments` resolves `parent_payment_key` **in-model** via a self-join on this load's own
key assignment (atomic + idempotent, vs. the sketch's second UPDATE pass); the behavior
snapshot appends one immutable period per month-end, all measures computed **as of** the
snapshot date, with a guard that makes a same-date re-run a no-op.

**4. Reconciliation as the acceptance test.** Every fact was proven against silver, not
assumed: sales \$2,987,210,221.51, payments \$1,864,219,754.32, lifetime value
\$3,294,663,372.11 — all exact to the cent, zero `-1` fallbacks. The snapshot's as-of logic was
proven by backfilling 2025-11-30: `orders_last_30_days` = 1,655 there vs. 0 at 2026-06-30.

**5. Lessons that only showed up by testing the incremental path:** a `::text` vs
`varchar(100)` cast passed `--full-refresh` but failed the incremental run
(`on_schema_change='fail'` doing its job) — always test both paths. And with no gold batches
logged yet, the batch watermark falls back to 1900-01-01, so fact runs are safe full reloads
until Airflow starts logging gold batches — a documented limitation, not a bug.

**6. First DRY macro.** The three role-playing date views are identical except the column
prefix, so the 15-column aliasing lives once in `macros/role_playing_date_view.sql` and each
view is a one-line call.

**Decisions recorded along the way:** ADR-015 written; backlog #5 (refund sign convention:
refunds stored negative, `SUM` nets automatically), #6 (18,2→12,2 narrowing verified safe:
max total \$196,382.98) and #10 (`po_number` added to `dim_invoice`) closed.

**Gold layer complete: 14/14 objects; warehouse-wide `dbt build --select silver gold` =
PASS 159. Released as `v0.2.0-gold`.**

**Proof in repo:** `dbt/printtime_dw/models/gold/` (all 14), `docs/adr/015-…`,
`docs/architecture/gold_star_schema.md`

## Lesson 10 — Orchestration: making the incremental loads actually incremental

**Concept:** every incremental mechanism built in Lessons 6–9 depended on batch bookkeeping that
did not exist yet. Silver stamped `silver_batch_id = -1` (the ad-hoc default) and the gold facts,
finding no succeeded gold batch, fell back to `1900-01-01` and reloaded everything on every run.
The models were correct; the loop was open. Wiring the DAG closed it.

**1. Where dbt runs (ADR-016).** dbt-core/dbt-postgres are installed in the Airflow image at
versions pinned identically to `docker/dbt`, with the project mounted at the same path. Chosen
over `DockerOperator`, which would have required mounting the host Docker socket into Airflow —
a real security cost to avoid duplicating two pinned lines. The dedicated dbt service stays for
ad-hoc work.

**2. Passing a runtime value into dbt from Airflow.** `start_silver_batch` opens a batch and
returns the key; XCom templating injects it into the dbt command:

```python
"--vars '{silver_batch_id: {{ ti.xcom_pull(task_ids=\"start_silver_batch\") }}}'"
```

Note this is **plain string concatenation, not an f-string** — the `{{ }}` must survive Python
so Airflow's Jinja can render it. An f-string would try to evaluate the braces at import time.

**3. Batch ordering is the whole trick.** Gold batches are opened *before* `dbt run --select
gold` and marked succeeded *after*. Because the facts read the last **succeeded** batch, run N
sees run N−1's timestamp — so a crashed run never advances the watermark and never causes silently
skipped data.

**4. Reading dbt's own results.** `target/run_results.json` carries `rows_affected` per model, so
the completion tasks record real row counts in `audit.etl_batch_control` instead of guessing. Read
it in the task *immediately after* the run it describes; treat missing entries as 0 (audit
metadata should never fail a load).

**5. Failure hygiene.** `fail_open_batches` (`trigger_rule=ONE_FAILED`) closes any batch a
crashed run left `running`. Without it a failure would strand rows forever — and worse, a later
manual completion could silently advance the fact watermark past unprocessed data. It is skipped
on clean runs.

**Two bugs that only running it could reveal** (both in `docs/fix/fix_log.md`):
- **FIX-001** — dbt could not write `logs/`/`target/` inside the mounted project, owned by the dbt
  container's user. Fixed with `DBT_LOG_PATH`/`DBT_TARGET_PATH` pointing at an Airflow-local dir,
  which also stops orchestrated and ad-hoc runs from overwriting each other's `run_results.json`.
- **FIX-002** — `batch_id` overflowed `VARCHAR(50)` on `gold.fact_customer_behavior_snapshot`
  (53 chars). Notably the *second* occurrence of that bug class: the first was patched by
  shortening the format rather than enforcing the width. Now the readable prefix is trimmed and
  the uniqueness-bearing epoch suffix never is.

**Proved end to end (5 DAG runs):** a clean run with `fail_open_batches` correctly skipped; a
failed run where it closed both stranded batches (0 left `running`); a no-change run where the
facts loaded **0 rows instead of 447k** and the DAG took ~60s instead of ~5min; and a genuine
source change — `state_name` edited in the **OLTP database** — that flowed to bronze → silver
(exactly 1 row rewritten, stamped with real batch 160; AZ/TX untouched at batch 42) → gold (every
California store and customer versioned via SCD2, facts correctly loading 0 rows because no
transaction changed).

**Proof in repo:** `airflow/dags/printtime_elt_pipeline.py`, ADR-016, `docs/fix/fix_log.md`

## Lesson 11 — DRY: a macro for the silver lineage/metadata block

**Concept:** a dbt macro is a Jinja function that expands into SQL *before* Postgres sees it, so
repeated SQL can live in one place without changing what runs. Every silver model closed its
cleaning SELECT with the same 11-column audit block (7 lineage columns from bronze + 4 of
silver's own stamping). Ten of the eleven were byte-identical across all 20 models, so the block
became one macro, `macros/silver_lineage_and_metadata.sql`, called once per model.

**1. The three pieces.** The **macro** is a template with `{{ }}` holes and fixed text between
them. The **call** is one line in each model — `{{ silver_lineage_and_metadata(
source_record_id='customer_id') }}`. The **expansion** is what `dbt compile`/`run` produces: the
call is replaced by the full 11-column block with the holes filled. dbt auto-discovers anything in
`macros/`, so there is no import.

**2. Parameterize only what varies.** Three columns differ by model, so they are the three
parameters — `source_record_id` (the natural key, required) and `source_created_at` /
`source_updated_at` (defaulting to `created_at`/`updated_at`). The two history tables have no
created/updated, only a change instant, so they override both to `changed_at_source_timestamp`.
The defaults encode the common case; the overrides make the exception explicit at the call site.

**3. `{{ var('silver_batch_id', -1) }}` rides along unchanged.** That hole was already dynamic
before the refactor — it is the hook Airflow fills via `--vars` (Lesson 10). An ad-hoc run stamps
`-1`; an orchestrated run stamps a real batch. The macro centralized it, it did not create it.

**4. What stayed OUT of the macro, deliberately.** The change-detection hash is computed over
*business* columns only, in a later CTE — never in this block — so metadata can never look like a
change. Folding it in would have coupled two things that must stay separate.

**5. Proving a refactor is a true no-op, not just "it built."** Touching 20 released models is
risky, so equivalence was proven three ways rather than assumed: `state.sql`'s compiled SQL is
byte-identical to the pre-macro version (whitespace-normalized diff empty); all 20 compiled models
contain exactly the 11 lineage columns; and `dbt build --select silver` = 95/95, the contracts
(`on_schema_change='fail'` + type/column enforcement) validating every schema. Postgres only ever
sees the expansion, so identical expansion = identical behavior.

**Payoff:** −264 lines, but the real value is that adding an audit column is now one edit instead
of twenty, and the models **cannot drift** from each other. Deliberately did NOT `--full-refresh`
silver to verify — that would refresh `silver_updated_at_timestamp` on every row and disturb the
gold incremental watermark; the incremental build + compiled-SQL proof covers correctness without
that side effect.

**Proof in repo:** `dbt/printtime_dw/macros/silver_lineage_and_metadata.sql`, the 20
`models/silver/*.sql` call sites.

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
| Space collapse | `regexp_replace(x, '\s+', ' ', 'g')` → identical strings, stable hash | Lesson 7 |
| Title Case vs preserve | `initcap` for persons; keep source case for businesses | Lesson 7 |
| Controlled vocabulary | explicit `case` maps to a closed set; junk → null | Lesson 7 |
| Derived columns | computed in silver from other columns (no bronze source) | Lesson 7 |
| History-tracked tables | one row per transition; `changed_at` ordering; never collapsed | Lesson 8 |
| Derived flag formulas | fixed in ADR-005; `paid_in_full = paid >= total` (excludes void) | Lesson 8 |
| Spec-first skill | read the governing spec before writing; spec wins | Lesson 8 |
| SCD2 via `append` | new version row + post-hook closes the old; merge = Type 1 | Lesson 9 |
| dbt-managed surrogate keys | model assigns keys; preserve from `{{ this }}`, new = max+offset | Lesson 9 |
| `-1` member, first build only | `UNION ALL` under `{% if not is_incremental() %}` | Lesson 9 |
| Fact key lookups | join dims on durable id + `is_current`; `coalesce(-1)` | Lesson 9 |
| In-model self-join resolution | refund chain resolved against this load's own keys | Lesson 9 |
| As-of snapshot measures | aggregate `<= snapshot_date`; same-date re-run = no-op | Lesson 9 |
| Reconcile, don't assume | fact totals compared to silver, exact to the cent | Lesson 9 |
| Test the incremental path | `--full-refresh` passing ≠ the incremental run passing | Lesson 9 |
| XCom → `--vars` | pass runtime values into dbt; concat, never an f-string | Lesson 10 |
| Batch open/close ordering | complete AFTER the run, so a crash can't advance the watermark | Lesson 10 |
| `run_results.json` | dbt's own `rows_affected` → real audit row counts | Lesson 10 |
| `ONE_FAILED` sweeper | close batches a crashed run stranded as `running` | Lesson 10 |
| Macro = pre-render | Jinja expands to SQL before Postgres sees it; DRY without runtime change | Lesson 11 |
| Parameterize the variance | fixed text in the macro, `{{ }}` holes only for what differs | Lesson 11 |
| Prove a refactor is a no-op | compiled SQL byte-identical + contracts pass, not just "it built" | Lesson 11 |

---

## Silver DONE (20/20) · Gold DONE (14/14) · Orchestration DONE

Warehouse-wide `dbt build --select silver gold` passes **159/159** (34 models + 125 tests).
The Airflow DAG runs the whole pipeline with real batch IDs, so the incremental loads are live.
Releases: `v0.1.0-silver`, `v0.2.0-gold`.

## Next up

- **DRY** — a macro for the repeated silver lineage+metadata block; consider one for the SCD2
  dim skeleton.
- **Regenerate the build guide** (`docs/dbt/PrintTimeUSA_dbt_Build_Guide.docx`) to cover gold
  and orchestration.
- **BI layer** — connect Power BI/Tableau to the star schema.
