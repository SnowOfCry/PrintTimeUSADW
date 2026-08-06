# Fix Log

PrintTimeUSA Data Warehouse. Bugs that actually bit us, what caused them, and the **class of
mistake** each one belongs to — so the same shape of bug is recognizable next time.

This is deliberately not a changelog. An entry earns its place only if the root cause was
non-obvious or the fix taught a reusable rule. Newest first.

**Related:** `docs/adr/` (decisions), `docs/dbt/dbt_decisions.md` (dbt implementation log),
`docs/backlog.md` (deferred work), `docs/audit/` (external audits).

---

## FIX-015 — a new entity arriving on an incremental run got `row_version = NULL`

| | |
|---|---|
| **Found** | 2026-08-06, code review of the SCD2 incremental path |
| **Symptom** | Latent — the incremental gold build **fails** (`null value in column "row_version" … violates not-null constraint`) the first time a brand-new entity arrives on an incremental run. Never fired because the current dataset loads every entity at the initial full-refresh build. |
| **Affected** | all six SCD2 dims (`dim_customer/store/cashier/product/invoice/payment_method`) |
| **Severity** | MEDIUM (correctness — blocks incremental onboarding of new entities) |

### Cause

Each SCD2 dim carries the existing version forward in the `changed` CTE and computes the next version in `keyed`:

```sql
-- changed (incremental branch)
, c.row_version as current_row_version     -- NULL for a brand-new entity
-- keyed
(current_row_version + 1) as row_version   -- NULL + 1 = NULL
```

On an incremental run, a brand-new entity has **no match** in the `left join {{ this }} c`, so `c.row_version` is NULL → `current_row_version` is NULL → `row_version = NULL + 1 = NULL`. The `{% else %}` (first-build) branch was already correct (`0::integer as current_row_version`); only the incremental branch was unguarded.

**What actually happens (and why the symptom is a *loud failure*, not silent corruption):** `row_version` carries a `not_null` **model-contract constraint**, enforced as a real DB `NOT NULL`. So the NULL is rejected at insert and the build fails — *no new entity can be onboarded incrementally.* Had the column been nullable, the same NULL would have cascaded silently: the entity's current version would have `row_version = NULL`, the close-out post-hook (`nv.row_version = d.row_version + 1`) could never match a NULL, the old version would never close, and the dim would end with **two `is_current` rows** (fanning out facts and failing `assert_scd2_one_current_version_per_entity`). The contract is what turned silent SCD2 corruption into a loud, safe failure (ADR-012).

### Fix

One-line null-guard in the incremental branch of all six dims, mirroring the first-build path:

```sql
, coalesce(c.row_version, 0) as current_row_version
```

A new entity now resolves to `current_row_version = 0 → row_version = 1 → valid_from = '1900-01-01'`, identical to the first-build path.

Verified: removed a customer from `dim_customer` so an incremental run saw it as new — with the old code the run **failed** with the NOT NULL violation; with the fix the row loaded as `row_version = 1`, `valid_from = '1900-01-01'`; then changing it produced `row_version = 2` with the old version correctly closed (one current version). `assert_scd2_one_current_version_per_entity` and `assert_scd2_row_version_contiguous` both pass; full suite 168/168 green. (No new test added — the `row_version` `not_null` contract already guards the invariant, more strongly than a test would.)

### Class of mistake

**Unguarded NULL from an outer join in incremental logic.** A `left join` to `{{ this }}` returns NULL for rows that don't exist yet — exactly the *new*-entity case an incremental model exists to handle. Any arithmetic or comparison on that carried-forward value must `coalesce` to the first-build default, or the "new" path silently diverges from the "first build" path.

---

## FIX-014 — batch_id fell back to a silent −1 on ad-hoc dbt runs

| | |
|---|---|
| **Found** | audit round 002 (MED-12); same pattern in gold (MED-10) |
| **Affected** | `macros/silver_lineage_and_metadata.sql`, `macros/gold_batch_id.sql` |
| **Severity** | MEDIUM (lineage integrity) |

### Cause

`silver_batch_id` was `{{ var('silver_batch_id', -1) }}` — an ad-hoc `dbt run --select silver` (no var) silently stamped **−1**. Once the orchestrated path supplies a real key, the column is *mostly* trustworthy with occasional −1 sentinels, which is a worse failure mode than uniformly-meaningless: it invites trust. Gold's `gold_batch_id()` had the same `-1` fallback (from MED-10).

### Fix

A `require_batch_id(name)` macro (and matching logic in `gold_batch_id()`) that is **loud on run/build** but harmless elsewhere:
- var supplied → use it;
- var absent **and** `execute` **and** `flags.WHICH in ('run','build')` → `raise_compiler_error` with guidance;
- otherwise (parse / compile / docs / test — nothing persisted) → return `-1` placeholder.

The `execute` guard is the crux: dbt renders *every* model's Jinja during the parse phase, so without it the raise would fire for unselected models too (e.g. the DAG's `dbt run --select silver` would wrongly demand the gold var). `execute` is true only when a **selected** model is actually being built, so the guard fires precisely for a model being run without its batch var. Applied to **both** silver and gold — resolving the MED-10/MED-12 inconsistency (gold no longer silently stamps `-1` either).

Verified: silver/gold run **without** the var fails loudly; the DAG's var-supplied `run --select silver` succeeds (gold not triggered); `dbt compile` / `dbt test` still work with no var; no test row was persisted with a placeholder.

### Class of mistake

**A sentinel that mixes with real data.** A default that "works" (−1) is worse than a loud failure once the column is *sometimes* real — consumers can't tell the sentinel from the truth. Fail on the operations that persist; stay quiet on the ones that don't.

---

## FIX-013 — compose secrets fell back to committed/empty defaults

| | |
|---|---|
| **Found** | audit round 001 (MED-8) |
| **Affected** | `docker-compose.yml` |
| **Severity** | MEDIUM (security) |

### Cause

Two Airflow secrets used `${VAR:-default}` fallbacks: `AIRFLOW__WEBSERVER__SECRET_KEY` fell back to the committed literal `changeme_in_env`, and `AIRFLOW__CORE__FERNET_KEY` fell back to empty (Airflow then generates an ephemeral key, so stored connection passwords can't be decrypted after a restart). Local-only today (ADR-002), but a default that works is a default that ships.

### Fix

Converted both to the fail-closed `${VAR:?message}` form — `docker compose up/config` now aborts with a clear message if the secret is unset, instead of silently using a weak default. Scoped to the two secrets the finding named (MED-8).

Verified: `docker compose config` passes with `.env` present; with the secret absent it fails loudly — `required variable AIRFLOW_SECRET_KEY is missing a value: AIRFLOW_SECRET_KEY must be set in .env`.

### Class of mistake

**A default that works is a default that ships.** A fallback secret removes the forcing function that would otherwise make a deployer set a real one; fail-closed keeps the guardrail.

---

## FIX-012 — pipeline could run concurrently; failure-sweeper wasn't run-scoped

| | |
|---|---|
| **Found** | audit round 002 (MED-11) |
| **Affected** | `airflow/dags/printtime_elt_pipeline.py` |
| **Severity** | MEDIUM (data integrity / orchestration) |

### Cause

The DAG set no `max_active_runs`, so two runs could overlap (a manual trigger during a scheduled run, or a long run spilling into the next day). Concurrent runs would share watermarks and `delete+insert` the same fact rows. Worse, `_fail_open_batches` failed **every** `running` batch for the pipeline (`initiated_by = PIPELINE`) without scoping to a run — so a failure in run A would mark run B's legitimately in-flight batches `failed`, corrupting B's audit trail and freezing its watermark.

### Fix

`max_active_runs=1` on the DAG — correct for any watermark-driven pipeline, and it fixes **both** symptoms at the root: with only one run ever active, there is no second run to corrupt, and the sweeper's existing `initiated_by = PIPELINE` filter is *automatically* scoped to the one active run.

**Decision (deviates from the audit's literal recommendation):** the audit also suggested scoping the sweeper to the batch keys this run pushed to XCom. Implemented faithfully, that would *regress* cleanup of stranded **bronze** batches — bronze batches are opened inside the ingest task and never pushed to XCom, so a hard-killed ingest would leave a `running` bronze batch the sweeper could no longer catch. `max_active_runs=1` already removes the actual (concurrency) bug without that regression, so the sweeper's whole-pipeline filter was kept (now run-scoped for free). Run-id-level scoping remains available as a future defense-in-depth if `max_active_runs` is ever removed.

Verified: `airflow dags details` reports `max_active_runs = 1`; DAG parses clean.

### Class of mistake

**Missing concurrency guard on stateful orchestration.** A watermark/`delete+insert` pipeline is not safe to run in parallel with itself; the default `max_active_runs` (16) silently allowed it. One line makes the whole design single-writer — and, as a bonus, made an unrelated sweeper correct.

---

## FIX-011 — no SCD2 integrity tests: the append + post-hook invariants were unguarded

| | |
|---|---|
| **Found** | audit round 001 (MED-5) |
| **Affected** | `dbt/printtime_dw/tests/` (new singular tests) |
| **Severity** | MEDIUM (data integrity / test coverage) |

### Cause

Gold had good generic tests (uniqueness, not-null, relationships, accepted-values) but nothing tested the **SCD2 invariants** the custom append + post-hook pattern can violate on a mid-run failure (insert succeeded, post-hook didn't → two current rows → the next run's effective-date join fans out and inserts duplicate versions). The audit named three: exactly one current version per entity, no overlapping validity ranges, and `row_version` contiguity.

### Fix

Three singular tests (all gate the watermark via `run_dbt_tests`, HIGH-7, so a violated invariant holds the pipeline instead of shipping fan-out):

- `assert_scd2_one_current_version_per_entity` — exactly one `is_current` per `source_record_id` (added earlier with the SCD2 effective-dating fix, FIX-005).
- `assert_scd2_no_overlapping_versions` — no entity has two versions whose `[valid_from, valid_to)` windows overlap (open/current windows treated as +∞; contiguous windows are fine).
- `assert_scd2_row_version_contiguous` — each entity's `row_version` set is exactly `{1..N}` (no gaps/dupes).
- **Bonus** `assert_fact_payments_refunds_are_negative` — every refund (resolved `parent_payment_key`) is stored negative, protecting the `SUM`-nets-refunds convention.

All six SCD2 dims are covered by each test. **Decision:** implemented as singular tests rather than adding `dbt_utils`/`packages.yml` — the finding is about the missing *tests*, not the tool, and singular tests close it with zero new dependency (adding dbt_utils would require wiring `dbt deps` into the DAG + both Docker images + CI, since `dbt_packages/` is gitignored).

Verified: all pass on clean data (168 tests green), and each detection query was proven to *catch* a seeded violation (two open versions → flagged; a `{1,3}` version gap → flagged) while leaving valid contiguous/adjacent cases alone.

### Class of mistake

**Untested invariants in hand-rolled logic.** A custom SCD2 pattern earns its flexibility but loses the guarantees a built-in would provide — so the invariants that make it correct have to be asserted explicitly, or a partial failure ships silently.

---

## FIX-010 — bronze ingestion hardening: watermark race, retry duplicates, snapshot stacking

| | |
|---|---|
| **Found** | audit round 001 (MED-2, MED-3, MED-7) |
| **Affected** | `ingestion/extract/oltp_extractor.py`, `ingestion/load/bronze_loader.py` |
| **Severity** | MEDIUM x3 (correctness / robustness / storage) |

Three related bronze-ingestion gaps, fixed together because they reinforce each other.

### MED-2 — watermark race could permanently miss rows

A row committed *after* an extract but timestamped *before* the captured max `updated_at` (an in-flight transaction) falls below a strict `> watermark` filter and is never picked up again. **Fix:** the extractor now filters `> (watermark − WATERMARK_LOOKBACK)` (default 1h) — a small overlap window that re-scans late-committing rows. It's free here because bronze appends, silver dedups to latest, and full-load tables hash-skip the unchanged re-reads. The **hard-delete gap** (watermark loads can't see physically-removed rows) is now explicitly documented in the bronze strategy doc rather than left silent.

### MED-3 — partial batch failure left orphans; retry duplicated them

Chunked `to_sql` committed every 20k-row chunk independently, so a mid-load crash left some rows landed under a `failed` batch, and the retry re-appended the whole window. **Fix:** the whole table load runs in **one transaction** (`engine.begin()`); any chunk failure rolls back all of them. No orphans, `rows_extracted`/`rows_inserted` stays exact, and bronze stays append-only (no delete-on-retry needed). Proven by injecting a failure on chunk 2 — chunk 1 rolled back too (row count unchanged).

### MED-7 — full-load tables stacked a full duplicate snapshot every run

11 reference/dimension tables re-appended their entire contents daily even when unchanged. **Fix:** full-load loads now **hash-skip** — a row whose `bronze_row_hash` matches the latest snapshot is not re-appended (the hash already covers the natural key, so unchanged rows hash identically). Proven: re-loading an unchanged table appended **0** rows. Incremental tables are deliberately *not* hash-skipped (matching against historical hashes could wrongly skip a legitimate revert; silver already absorbs the tiny lookback re-read).

**Also:** `bronze_loader` now validates its target-table identifier (same pattern as FIX-009) since MED-7 interpolates the table name into a snapshot query. Unit tests updated + extended.

### Class of mistake

**Boundary and idempotency assumptions.** MED-2 trusted timestamp order to equal commit order; MED-3 trusted a multi-statement load to be all-or-nothing without a transaction; MED-7 trusted "append everything" to be cheap forever. Each is fine until scale or concurrency makes the hidden assumption bite.

---

## FIX-009 — extractor built SQL by f-string interpolation (value + identifiers)

| | |
|---|---|
| **Found** | 2026 audit round 001 (finding MED-1) |
| **Symptom** | `WHERE {watermark_column} > '{last_value}'` — the watermark value was interpolated into the SQL string via `str()`, and table/column names were interpolated too. |
| **Affected** | `ingestion/extract/oltp_extractor.py` + its unit tests |
| **Severity** | MEDIUM (security / robustness) |

### Cause

`_build_incremental_query` and `_build_full_load_query` returned f-string SQL. The **value** round-tripped through `str()` (pandas Timestamp → string → SQL literal) — fragile against timezone/precision — and any name reaching the string was an injection surface. Low risk today (inputs come from `ingestion_config.yml`), but a latent hazard for any future/direct caller.

### Fix

- **Value → bound parameter.** The builders now return a SQLAlchemy `text()` clause plus a params dict; the watermark is bound (`> :watermark`) and passed to `pd.read_sql(..., params=...)`, so the driver sends it with its real type. No `str()` literal, no value injection.
- **Identifiers → validated.** Table/column names can't be bound (they're SQL identifiers), so a `_validate_identifier()` guard rejects anything outside `[A-Za-z_][A-Za-z0-9_]*`. The true allowlist is already enforced upstream (`main.py` resolves the table from `ingestion_config.yml`); this is the reusable-class safety net.
- Unit tests updated to the `(text, params)` signature + new coverage that injection payloads (`"customer; drop table x"`, `"updated_at) OR 1=1"`, …) raise `ValueError`.

Verified: the built query is `SELECT * FROM invoice WHERE updated_at > :watermark` with the value in params (never in the SQL text); a real bound-param query ran against the OLTP source; all injection payloads rejected.

### Class of mistake

**String-built SQL.** Even with trusted inputs, interpolating values into SQL is fragile (type round-trips) and one refactor away from injection. Values belong in bind params; identifiers, which can't be bound, belong behind an allowlist/validation.

---

## FIX-008 — gold indexes silently dropped by `--full-refresh`, never recreated

| | |
|---|---|
| **Found** | 2026-07-28, external audit round 002 (finding MED-9); confirmed live 2026-08-05 |
| **Symptom** | The gold star had **0 of its ~33 performance indexes** — every fact FK-join and SCD2 lookup ran unindexed. |
| **Affected** | all 11 gold models; `sql/gold/003_create_gold_indexes.sql` |
| **Severity** | MEDIUM (performance) |

### Cause

The indexes were **DDL-managed** (`sql/gold/003`), but the gold **tables are dbt-managed** (ADR-015 #7). `dbt --full-refresh` does `DROP TABLE … CREATE TABLE …`, which drops the indexes, and dbt had no knowledge of `sql/gold/003`, so they were never recreated. Every full-refresh this session had quietly left gold completely unindexed — verified: 11 indexes present (all PK/unique), 0 of the 33 `idx_*`.

### Fix

Moved index management **into the dbt models** using dbt-postgres's declarative `indexes=[…]` config — one entry per index, replicating `sql/gold/003` exactly across all 11 gold models. dbt now (re)creates them on every build/full-refresh, so they cannot drift from the table. `sql/gold/003` was annotated **bootstrap/spec-reference only**; the dbt config is authoritative at runtime.

Verified: a `dbt run --select gold --full-refresh` — the exact operation that used to drop them — now **creates** all 33 indexes (gold went 11 → 44 total); 165/165 tests pass.

### Class of mistake

**Two owners for one object.** The tables were dbt's; the indexes were the DDL's — so a dbt operation silently discarded DDL-owned state. Lesson: whatever tool materializes an object must own everything attached to it (indexes, constraints, grants), or a rebuild will drop what it doesn't know about.

---

## FIX-007 — `audit.audit_log` never written: fact reloads destroyed rows with no trail

| | |
|---|---|
| **Found** | 2026-07-28, external audit round 002 (finding MED-4) |
| **Symptom** | The `delete+insert` facts overwrote rows on every reload with **no record** of the prior values; `audit.audit_log` (built for exactly this) was never written. |
| **Affected** | `fact_retail_sales`, `fact_payments` + a new macro file; `sql/security/001_create_roles.sql` |
| **Severity** | MEDIUM (governance / change tracking) |

### Cause

`audit.audit_log` — the designed insert-only change trail (ADR-008), which ADR-013 §4 also relies on for CCPA erasure logging — had **no writer**. The two facts reload by `delete+insert`, so the old fact rows were gone with no before-image. (SCD2 dimensions don't have this gap — they *keep* the old version in-table, so their history is self-documenting; MED-4 is facts-only.)

### Fix

A `pre_hook`/`post_hook` pair on each `delete+insert` fact, both inside the model's transaction (atomic with the reload):

- **pre_hook** `audit_stage_before_image()` — stages the before-image of the rows about to be deleted (the *same* changed-set the model reloads, via a shared `changed_*` macro, so captured = replaced) into a **session temp table**.
- **post_hook** `audit_write_change_log()` — writes **one insert-only** `audit_log` row per staged row, pairing it to its replacement by the durable `source_record_id` to fill `new_row` + `changed_columns` (business columns only — the regenerated surrogate key and load-metadata timestamps are excluded, or every reload would look fully changed). A staged row with no surviving fact row → `DELETE`.
- `change_reason` is best-effort from `silver.invoice_adjustment.silver_adjustment_reason`, else `'source_update'`; `etl_batch_id` is the real batch id (FIX-006).

**Spec decision:** the first cut used a `post_hook` `UPDATE` to fill the after-image, but the DDL/ADR-008 say `audit_log` is *"insert-only … never updated."* Reworked to the temp-staging pattern so `audit_log` only ever receives INSERTs, and `pt_dbt` was granted **INSERT on `audit_log` only** (not `etl_batch_control`) — least privilege intact.

Verified end-to-end: editing one invoice line logged `old_row` 392.70 → `new_row` 999.99 with `changed_columns = ["gross_profit","sales_amount"]`, the real batch id, and the reason; the untouched line of the same reloaded invoice logged `changed_columns = NULL`. 165/165 tests pass.

### Class of mistake

**Designed but unwired capability** (same family as FIX-006). The table, its columns, and two ADRs describing it all existed; nothing wrote to it. And the fix surfaced a second lesson: an *insert-only* invariant is a real constraint — the obvious "insert then update to fill" approach violates it, so stage-then-insert-once is the faithful pattern.

---

## FIX-006 — gold rows stamped `etl_batch_id` NULL: row-level lineage was broken

| | |
|---|---|
| **Found** | 2026-07-28, external audit round 002 (finding MED-10) |
| **Symptom** | Every gold row had `etl_batch_id = NULL`, so the documented join `gold.etl_batch_id → audit.etl_batch_control.batch_id` was impossible. |
| **Affected** | all 9 gold models with the column + `airflow/dags/printtime_elt_pipeline.py` |
| **Severity** | MEDIUM (governance / lineage) |

### Cause

The gold batch machinery was fully built but the last wire was missing. `_start_gold_batches` opened one batch per target and returned `{target: batch_key}` via XCom, but `run_dbt_gold` ran `dbt run --select gold` with **no `--vars`**, so the models fell back to a hardcoded `null::varchar(50) as etl_batch_id`. Silver did it correctly (`--vars silver_batch_id`), but gold was never given the key.

### Fix

- `_start_gold_batches` now also captures the **text `batch_id`** per target and pushes a `gold_batch_ids` map as an XCom (`gold_vars_json`).
- `run_dbt_gold` templates that map into `--vars` (string-concatenated so the `{{ }}` survives Airflow templating — same HIGH-7-safe pattern as `run_dbt_silver`).
- New macro `gold_batch_id()` resolves each model's own id: facts use their own target (`gold.<model>`), every dimension resolves to the shared `gold.dimensions` batch (ADR-008 — dims load as one batch). All 9 models stamp `'{{ gold_batch_id() }}'::varchar(50)`; `-1` fallback for ad-hoc runs.

**Two spec corrections vs. the naive approach:** (1) gold stamps the **text `batch_id`**, not the integer `batch_key` silver uses — the naming convention joins on `batch_id`; (2) dims **share** one `gold.dimensions` batch by design, so "each dim its own key" means each target's key, not one-per-dim.

Verified: every non-seed gold row joins cleanly to `etl_batch_control.batch_id` (the `-1` seed members stay NULL by design); 165/165 tests pass.

### Class of mistake

**Last-wire-missing.** The hard parts (batch lifecycle, watermark, XCom map) were all built and working; a single un-passed `--vars` left the whole feature inert with a silent NULL default. Lesson: a hardcoded `null as x` placeholder is a smell — grep for them before calling a lineage feature done.

---

## FIX-005 — SCD2 was Type-1 in disguise: load-date dating + `is_current` fact joins

| | |
|---|---|
| **Found** | 2026-07-28, external audit round 002 (finding HIGH-3) |
| **Symptom** | Latent — every entity currently has one version, so results looked right. The bug only bites once a dimension attribute changes. |
| **Affected** | all six SCD2 dims (`dim_customer/store/cashier/product/invoice/payment_method`) + `fact_retail_sales`, `fact_payments`, `fact_customer_behavior_snapshot` |
| **Severity** | HIGH (modeling correctness) |

### Cause

Two mistakes that together defeated the whole point of Type 2:

1. **Versions were dated by load date.** `valid_from = CURRENT_DATE` and the post-hook closed the old version at `CURRENT_DATE` — so a version's validity window recorded *when the ETL ran*, not *when the change happened*. A change loaded a week late (or backfilled) was dated a week late.
2. **Facts resolved keys on `is_current`.** Every fact joined the dimension `AND dim.is_current`, grabbing the entity's **latest** version regardless of when the event occurred. A 2020 sale for a customer renamed in 2023 would be attributed to the 2023 name. This is Type-1 (overwrite) behaviour wearing a Type-2 costume — the storage cost of history with none of the accuracy.

The reason it was invisible: with exactly one version per entity, `is_current` *is* the only version, so the numbers happened to be right. The defect is structural, not observable in the current data.

### Fix

- **Date versions by the source effective date.** New version `valid_from = silver_source_updated_at_timestamp::date`; the post-hook closes the prior version at the **next** version's `valid_from` → contiguous half-open windows `[valid_from, valid_to)`. The initial version uses a low-watermark `DATE '1900-01-01'` (the source has no pre-load history), so it covers all facts predating the first change.
- **Resolve fact keys by effective date.** Replace `AND dim.is_current` with `event_date >= dim.valid_from AND (event_date < dim.valid_to OR dim.valid_to IS NULL)`, `-1` fallback intact.
- **Guard test** `assert_scd2_one_current_version_per_entity` so an entity can never again end up with 0 or 2 current versions.

Proven by renaming a customer effective 2023-06-15: pre-date sales stayed with the old version, post-date sales moved to the new one; reconciliation-to-the-cent stayed green. See ADR-015 (Correction, 2026-08-04).

### Class of mistake

**Building the machinery but not the semantics.** The SCD2 scaffolding (versions, `valid_from/to`, `is_current`, `row_version`) was all present and *looked* complete, so it passed casual review — but the two operations that give it meaning (effective-date *dating* and effective-date *lookup*) were both keyed off the wrong thing. Lesson: for a temporal model, test it *with* a change, not just at rest — a Type-2 dimension with no second version can't tell you whether it's actually Type 2.

---

## FIX-004 — data-quality tests ran *after* the gold watermark was committed

| | |
|---|---|
| **Found** | 2026-07-29, external audit round 002 (finding HIGH-7) |
| **Symptom** | Latent — never observed. A failing gold test would fail the DAG *after* the bad data was already committed and the watermark had moved past it. |
| **Affected** | `airflow/dags/printtime_elt_pipeline.py` — task ordering |
| **Severity** | HIGH (data integrity); the highest-value item the audit found |

### Cause

The DAG chain ran `complete_gold_batches` *before* `run_dbt_tests`:

```
run_dbt_gold → complete_gold_batches → run_dbt_tests
```

`complete_gold_batches` marks the gold batches `succeeded`, and the facts' incremental watermark
reads the *last succeeded* gold batch. So the watermark advanced **before** any test ran. A test
failure then failed the DAG, but the bad rows were already in gold and the watermark had already
moved past them — the next run would skip straight over the unvalidated data. With
`email_on_failure: False` and no callback, the failure also notified no one. The pipeline
committed state before it verified it.

### Fix

Reorder so validation gates the commit:

```
run_dbt_gold → run_dbt_tests → complete_gold_batches
```

Now a test failure leaves `complete_gold_batches` `upstream_failed`, the gold batches stay
`running`, `fail_open_batches` marks them `failed`, and the watermark never advances — the next
run reprocesses. One subtlety: `dbt test` overwrites `target/run_results.json`, which
`complete_gold_batches` reads for its row counts, so the test run is redirected to a separate
`DBT_TARGET_PATH` to leave the gold run's results intact.

`complete_silver_batch` deliberately stays before the tests: silver's watermark is row-based
(each model reads `max(silver_bronze_batch_id)` from its own table), so it advances when rows are
written regardless of the audit batch status — its completion is bookkeeping, not a gate.

### Proof

Verified end to end, not just reasoned: captured the watermark (succeeded `fact_retail_sales`
batch 338), added a temporary always-failing dbt test, and ran the DAG. `run_dbt_tests` failed →
`complete_gold_batches` was skipped → the run's gold batches were swept to `failed` → **the
watermark stayed at 338**, unmoved. Removing the test and re-running advanced it to 388. Before
the fix, that failed run's batch would have been `succeeded` and the watermark would have moved.

### Rule

> **Validation must gate state commitment, not trail it.** A batch, watermark, or checkpoint may
> be marked complete only *after* the data it covers has passed its checks — never before. If a
> pipeline commits state before it verifies it, a failed check fails loudly while the bad data has
> already escaped.

---

## FIX-003 — `batch_id` uniqueness depended on the wall clock advancing

| | |
|---|---|
| **Found** | 2026-07-28, while writing the regression test for **FIX-002** |
| **Symptom** | Latent — never fired in production. Surfaced as a failing unit test: 50 ids generated in a tight loop were not all distinct. |
| **Would have surfaced as** | `UniqueViolation` on `uq_etl_batch_control_batch_id`, failing a DAG task |
| **Affected** | `ingestion/utils/batch_control.py` → `build_batch_id()` |
| **Severity** | Low probability, task-fatal impact |

### Cause

`batch_id` derives its uniqueness entirely from a microsecond timestamp:

```python
suffix = f":{int(datetime.now().timestamp() * 1_000_000)}"
```

That is only unique if the clock actually advances between calls. It does not always: the DAG's
`_start_gold_batches` opens **four batches in a tight loop**, and any two landing in the same
microsecond produce identical ids and collide against the UNIQUE constraint.

It had never fired because each call happens to make a DB round trip (~1 ms), which is far longer
than the clock's resolution. That is luck, not design — the guarantee lived in the *timing of an
unrelated I/O call*, not in the code.

### How it was found

This is the interesting part. FIX-002 recurred precisely because the id-building was **inline
inside `start_batch()`**, which opens a database connection and therefore could not be unit
tested. Closing FIX-002 properly meant extracting a pure `build_batch_id()` so the width
guarantee could be asserted.

The moment it became testable, a *different* assertion failed — the uniqueness one. The original
bug had been hiding a second defect in the same function.

### Fix

Make the epoch strictly increasing per process, independent of clock resolution:

```python
_epoch_lock = threading.Lock()
_last_epoch_micros = 0

def _next_epoch_micros() -> int:
    global _last_epoch_micros
    with _epoch_lock:
        now = int(datetime.now().timestamp() * 1_000_000)
        if now <= _last_epoch_micros:
            now = _last_epoch_micros + 1
        _last_epoch_micros = now
        return now
```

The lock matters because Airflow may run tasks concurrently; across separate processes the wall
clock still separates them. Verified with 500 ids generated in a tight loop — all distinct and
monotonically increasing (`tests/unit/test_batch_control.py`).

### Rule

> **A bug you cannot unit test will come back.** If fixing something requires extracting it into a
> pure function to make it testable, that extraction *is* part of the fix — and the new test may
> well find a second defect the original bug was hiding.

A companion rule from the cause itself:

> **Don't let a correctness guarantee rest on incidental timing.** If uniqueness depends on "the
> clock will have moved by then", it depends on how fast the surrounding code happens to run.

---

## FIX-002 — `batch_id` overflowed `VARCHAR(50)` on gold target names

| | |
|---|---|
| **Found** | 2026-07-28, first orchestrated gold run (`start_gold_batches` task) |
| **Symptom** | `psycopg2.errors.StringDataRightTruncation: value too long for type character varying(50)` |
| **Affected** | `ingestion/utils/batch_control.py` → `start_batch()` |
| **Severity** | Blocked the whole gold half of the DAG |

### Cause

`batch_id` was built by plain concatenation:

```python
batch_id = f"{target_table}:{epoch_micros}"
```

The longest gold target overflows the column:

```
gold.fact_customer_behavior_snapshot   36
:                                       1
1785273477728790                       16   (epoch microseconds)
                                     ────
                                       53   > VARCHAR(50)
```

Bronze never triggered it — its longest name (`oltp_customer_status_history`, 28 chars) totals
45. The bug lay dormant through the entire bronze and silver phase and only fired when gold
introduced longer table names.

**The aggravating detail:** the line above it already said *"Keep batch_id within VARCHAR(50)"*.
The intent was documented; nothing enforced it. A comment is a wish — only code is a guarantee.

**This was the second occurrence of the same class.** An earlier version used
`{pipeline}:{table}:{epoch_ms}` and overflowed during the bronze build. That fix shortened the
*format* (dropped `pipeline`) — it removed the symptom for the names that existed at the time,
but never added enforcement, so the bug simply waited for longer names.

### Fix

```python
_BATCH_ID_MAX_LEN = 50          # matches audit.etl_batch_control.batch_id

suffix   = f":{int(datetime.now().timestamp() * 1_000_000)}"
batch_id = f"{target_table[: _BATCH_ID_MAX_LEN - len(suffix)]}{suffix}"
```

Three deliberate choices:

1. **Trim the prefix, never the suffix.** The epoch is what makes the id UNIQUE; truncating it
   would risk collisions against `uq_etl_batch_control_batch_id`. The readable prefix is the safe
   thing to lose.
2. **No information is lost.** The full name is stored in `target_table VARCHAR(100)`;
   `batch_id` is only an external identifier.
3. **The limit is a named constant tied to the DDL**, not a magic number inside an f-string.

Longest name now lands at exactly 50: `gold.fact_customer_behavior_snaps:1785273477728790`

### Rule

> **When a string is assembled from variable-length parts and stored in a fixed-width column,
> the code must enforce the width.** If a comment states a constraint, there should be a constant
> enforcing it.

Habits that would have caught it:

- **Test with the longest realistic input**, not a convenient one. `state` (5 chars) passes
  everything; `gold.fact_customer_behavior_snapshot` is the honest test.
- **Fix the class, not the instance.** The first overflow was patched by shortening the format;
  had it been patched with enforcement, there would have been no second occurrence.

**Follow-up:** writing the regression test for this fix exposed a second, independent defect in
the same function — see **FIX-003**.

---

## FIX-001 — dbt `PermissionError` writing `logs/` and `target/` under Airflow

| | |
|---|---|
| **Found** | 2026-07-28, first orchestrated `run_dbt_silver` task |
| **Symptom** | `PermissionError: [Errno 13] Permission denied: '/dbt/printtime_dw/logs/dbt.log'` |
| **Affected** | Airflow ↔ dbt (`docker-compose.yml`) |
| **Severity** | Blocked every dbt task in the DAG |

### Cause

dbt always writes `logs/dbt.log` and `target/` next to the project. That project directory is
mounted into **two different services that run as different users**:

```
./dbt/printtime_dw  →  dbt container      (its own user)
./dbt/printtime_dw  →  airflow containers (user "airflow", uid 50000)
```

Earlier ad-hoc `docker compose run --rm dbt ...` invocations created `logs/` and `target/` owned
by the dbt container's user. When Airflow later tried to write there, the OS refused.

Note the failure happened **before a single model ran** — dbt initializes logging first — so the
error had nothing to do with the SQL, which made the message initially misleading.

### Fix

Give Airflow its own artifact location rather than contend for the shared one (dbt-native env
vars, so no code changed):

```yaml
DBT_LOG_PATH:    /opt/airflow/dbt_artifacts/logs
DBT_TARGET_PATH: /opt/airflow/dbt_artifacts/target
```

`/opt/airflow/` lives inside the Airflow container and is owned by the airflow user. The DAG
reads `run_results.json` from the matching path
(`/opt/airflow/dbt_artifacts/target/run_results.json`).

**Second benefit:** orchestrated and ad-hoc runs no longer overwrite each other's
`run_results.json`. Had they shared it, a DAG task could have reported row counts from a manual
run — a silent data-quality lie in the audit log.

### Rule

> **When one host folder is mounted into containers that run as different users, whoever writes
> first owns it.** Give each writer its own path; don't reach for `chmod 777`.

Watch for this whenever a second service starts mounting an existing volume, or when
`Permission denied` appears on a path that demonstrably exists.

---

## Earlier fixes (condensed)

Kept short — each was resolved during the build and is recorded in the relevant commit.

| Area | Symptom | Cause & fix |
|---|---|---|
| Ingestion | `'Engine' object has no attribute 'cursor'` | pandas 2.2 requires SQLAlchemy ≥2.0 connectables; Airflow 2.9.3 pins SQLAlchemy 1.4. Pinned `pandas==2.1.4`. |
| Ingestion | Bronze loader OOM on `invoice_line` (390k rows) | Whole frame converted + buffered at once. Chunked at 20k rows (`LOAD_CHUNK_ROWS`). |
| Ingestion | `invalid input syntax for type json` | NULL numerics became float `NaN`, which Postgres JSON rejects. `df.astype(object).where(df.notna(), None)`. |
| dbt | `create schema if not exists ""` | `generate_schema_name` macro lost its `{%- else -%}` branch, so it returned an empty string. Restored the branch. |
| dbt | Model built but constraints missing | `CREATE TABLE AS SELECT` silently drops `NOT NULL`/PK. Enabled model **contracts** (declare-then-insert). |
| dbt | `on_schema_change 'ignore' invalid` | incremental + contract forbids the default. Chose `'fail'` — schema drift should be loud. |
| dbt | `--full-refresh` passed, incremental run failed | A `::text` cast vs a `varchar(100)` contract. The full refresh coerced it; the incremental insert did not. **Always test both paths.** |
| Gold | SCD2 dim collapsed to one row per key | `incremental_strategy='merge'` overwrites in place = Type 1. SCD2 requires `append` + a post-hook to close the prior version (ADR-015). |

---

## How to add an entry

Add a numbered section at the top (newest first) with: symptom, cause, fix, and — the part that
matters most — the **rule** it generalizes to. If a bug produced no reusable rule, it probably
belongs in a commit message rather than here.
