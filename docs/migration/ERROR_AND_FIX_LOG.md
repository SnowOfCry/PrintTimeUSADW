---
title: Databricks Migration — Error & Fix Log
tags: [databricks, migration, dbt, troubleshooting, data-engineering]
created: 2026-09-15
status: living-document
---

# Databricks Migration — Error & Fix Log

A running log of every problem hit while migrating the PrintTimeUSA data warehouse
from local **Postgres** to **Azure Databricks** (proven first on **Databricks Free Edition**),
and exactly how each was fixed. Kept for future-me, teammates, and interviews.

> **How to read this:** each entry has **Symptom → Cause → Fix → Lesson**. The Lesson
> is the transferable part — the thing worth remembering after the specific error is gone.

---

## Environment / setup issues

### 1. `pip` / `python` not recognized
- **Symptom:** `'pip' is not recognized as an internal or external command`. `python` opened the Microsoft Store instead.
- **Cause:** Python was never installed natively — the whole project ran in **Docker**, so the OS only had Windows' "App execution alias" stubs for `python`/`python3`.
- **Fix:** Installed real Python via `winget install -e --id Python.Python.3.12`, opened a **new** terminal (PATH only refreshes in new shells), verified `python --version`.
- **Lesson:** A dockerized project doesn't guarantee local tooling. Running dbt **Core** locally needs a real local Python. If the Store stub keeps hijacking, turn off the `python.exe` App execution aliases in Windows Settings.

### 2. Virtual environment created but `dbt` installed globally
- **Symptom:** `(.venv)` showed in the prompt, yet `dbt debug` reported the **global** Python path, and `.venv/Scripts/` had no `dbt.exe`.
- **Cause:** `pip install dbt-databricks` ran while the venv was **not active** (installed during a fresh terminal), so it landed in global Python. Later the active venv found the global `dbt.exe` on PATH.
- **Fix:** Functional as-is (dbt runs from global). Clean version: activate the venv **before** `pip install`, or reinstall inside it: `.venv\Scripts\activate` then `pip install dbt-databricks`.
- **Lesson:** Activate the venv **before** installing anything. Verify with `pip -V` / `where dbt` pointing inside `.venv`. The prompt showing `(.venv)` is not proof that a tool resolves to the venv.

### 3. `dbt debug` can't find the project / wrong directory
- **Symptom:** `fatal: not a git repository`, or dbt not finding `dbt_project.yml`.
- **Cause:** Commands run from the wrong folder. In **cmd**, `cd ~/OneDrive/...` does **not** work — `~` is a bash-ism, not understood by cmd.
- **Fix:** Use a full Windows path with the drive switch: `cd /d C:\Users\offic\OneDrive\Desktop\PrintTimeUSADW`.
- **Lesson:** cmd ≠ bash. No `~`, no `grep`, no forward-slash home paths. Know which shell you're in. (`findstr` is cmd's `grep`.)

### 4. dbt does not auto-load `.env`
- **Symptom:** `env_var()` values were empty / connection undefined even though `.env` existed.
- **Cause:** dbt reads OS **environment variables**, but it does **not** read a `.env` file on its own.
- **Fix:** Installed `python-dotenv[cli]` and prefixed commands with `dotenv run --`, which loads `.env` into the environment for that one command:
  `dotenv run -- dbt run ...`
- **Lesson:** A `.env` file is inert until something loads it. `dotenv run --` (or `direnv`, or manual `set`/`export`) is what injects it.

### 5. `.env` vs `.env.example` confusion
- **Symptom:** Edited `.env.example` (full of `changeme_*` placeholders) instead of creating `.env`.
- **Cause:** Two similarly named files. `.env.example` is a **committed template**; `.env` is the **real, git-ignored** file you create.
- **Fix:** Created a separate `.env` with only the five variables the Databricks connection needs (host, http_path, token, catalog, schema).
- **Lesson:** `*.example` files are documentation. Your real secrets go in the git-ignored twin. Never edit or commit the real one.

### 6. Local repo was 139 commits behind GitHub
- **Symptom:** Local `main` looked older than expected; a stale `feature/gold-layer` was checked out.
- **Cause:** Local clone hadn't been fetched/pulled in a long time; `origin/main` had advanced 139 commits (gold + orchestration releases).
- **Fix:** `git fetch origin`, then `git checkout main && git pull --ff-only origin main` to fast-forward to match GitHub. Then branched migration work off the synced `main`.
- **Lesson:** Before starting new work, **sync to origin** and confirm your base. `git rev-list --left-right --count origin/main...main` shows behind/ahead. `--ff-only` refuses messy merges — a safety guard.

---

## Databricks / dbt-databricks issues

### 7. `[UNSUPPORTED_DATATYPE] Unsupported data type "TEXT"`
- **Symptom:** `dbt run` failed with `cast(null as text)` — `TEXT` unsupported (SQLSTATE 0A000).
- **Cause:** The failing SQL was a dbt **introspection query** (`... where false limit 0`) built from the model's **YAML contract** (`_silver_models.yml`, `contract: enforced: true`). Those `data_type:` declarations were **Postgres types** (`text`, `varchar(n)`). `text` is not a Databricks type.
- **Fix:** Translated the contract types: `data_type: text` → `data_type: string` (43 occurrences in the silver contract). `varchar(n)` is accepted by Databricks, so only `text` strictly required the change.
- **Lesson:** **Postgres dialect hides in YAML too, not just SQL.** With enforced contracts, `data_type:` declarations must be valid Databricks types. Map: `text`/`varchar(n)`/`char(n)` → `string`; `numeric(p,s)` → `decimal`/`numeric` (accepted); `integer`/`bigint`/`smallint`/`boolean`/`date`/`timestamp` → unchanged.

### 8. Git Bash mangled the SQL Warehouse `http_path` → 404
- **Symptom:** `http-code=404, method=OpenSession` on every run — *after* earlier runs had worked with the same `.env`.
- **Cause:** The 404 runs were executed from **Git Bash (MSYS)**, whose POSIX-path conversion rewrote `/sql/1.0/warehouses/...` into `C:/Program Files/Git/sql/1.0/warehouses/...`. The working runs were from **cmd**, which leaves the path alone.
- **Fix:** Run dbt from **cmd** (or PowerShell), not Git Bash. If Git Bash is unavoidable, set `MSYS_NO_PATHCONV=1` to disable path mangling.
- **Lesson:** A value starting with `/` is dangerous in Git Bash — it silently becomes a Windows path. When a URL/path "works in one terminal but 404s in another," suspect shell path conversion. Confirm with `dbt debug` — it prints the **resolved** `http_path`.

### 9. SQL Warehouse asleep → `404 OpenSession`
- **Symptom:** Same 404 when the warehouse had auto-stopped.
- **Cause:** Free Edition serverless warehouses auto-stop after a short idle; a cold endpoint can 404 instead of transparently waking.
- **Fix:** Start the warehouse in the UI (**SQL → SQL Warehouses → Start**), wait for **Running**, then re-run. It then stays warm for the auto-stop window.
- **Lesson:** For interactive dev, start the warehouse first and keep it warm. Distinguish this from #8 — check the **resolved** http_path before blaming the warehouse.

### 10. Incremental model refused to run without a batch id
- **Symptom:** Would-be compile error if `dbt run` lacked a var.
- **Cause:** The `require_batch_id('silver_batch_id')` macro **deliberately** raises on `run`/`build` when the var is missing, so lineage is never stamped with a fake sentinel.
- **Fix:** Passed the var: `dbt run --select customer --vars "{silver_batch_id: 1}"`. (In production the orchestrator supplies it.)
- **Lesson:** Some projects gate persistence behind required vars on purpose. Read the macro before "fixing" the error — the loud failure is a feature.

### 11. `WARNING: unenforced constraint type: primary_key`
- **Symptom:** Warnings on a successful run about `primary_key` / constraints being unenforced.
- **Cause:** Databricks/Delta accepts constraint metadata but does **not enforce** primary keys the way Postgres does.
- **Fix:** None needed — informational. (Data-quality enforcement moves to dbt tests: `unique`, `not_null`.)
- **Lesson:** Not every warning is a problem. On Databricks, **tests replace enforced constraints** for uniqueness/not-null guarantees.

### 12. Automating the cast port — and its two parser traps
- **Symptom:** Hand-porting 48 models (hundreds of `::` casts) is too slow and error-prone.
- **Cause:** Postgres `expr::type` has no Spark equivalent; every one needs `cast(expr as type)`.
- **Fix:** Wrote a Python cast-boundary parser (`scratchpad/port_pg_to_databricks.py`) that walks left from each `::` to find the operand (balancing parens, and extending `end` back to its matching `case`), then rewrites to `cast(... as <mapped type>)`. Also drops the `regexp_replace` `'g'` flag, doubles regex backslashes, and fixes `now()`/`current_*`.
- **Traps it hit (both fixed):**
  1. Paramless types (`::bigint`) greedily ate trailing whitespace → `)as` instead of `) as`. Fix: move `\s*` **inside** the optional `(params)` group in the type regex.
  2. `count(*) FILTER (...)::int` — the parser grabbed only the `(...)` and the word `FILTER`, producing broken `FILTER cast((...))`. Fix: hand-corrected the 2 affected lines to `cast(count(*) FILTER (...) as int)`.
- **Lesson:** Automate the mechanical 95%, but **always** grep the output for the constructs a naive parser mishandles (`FILTER cast(`, `cast((where`, unbalanced results) and eyeball the densest file before trusting it.

### 13. `Cannot resolve routine 'digest'` (UNRESOLVED_ROUTINE)
- **Symptom:** SCD2 dims failed: `Cannot resolve routine 'digest'`.
- **Cause:** Postgres hashed with pgcrypto: `encode(digest(concat_ws('|', ...), 'sha256'), 'hex')`. Databricks has no `digest`/`encode`.
- **Fix:** `encode(digest(X, 'sha256'), 'hex')` → `sha2(X, 256)` (returns the hex string directly).
- **Lesson:** Postgres crypto/encoding funcs don't exist on Databricks. Map: `digest+encode` → `sha2`; `md5` stays `md5`.

### 14. `UPDATE ... FROM` not supported (SCD2 close-out)
- **Symptom:** `PARSE_SYNTAX_ERROR ... at or near 'from'` in the SCD2 dims' `post_hook`.
- **Cause:** The post-hook closed the previous current version with a Postgres join-update: `update {{ this }} d set is_current=false, valid_to=nv.valid_from from {{ this }} nv where ...`. Spark SQL has **no `UPDATE ... FROM`**.
- **Fix:** Rewrote each as `MERGE INTO {{ this }} d USING {{ this }} nv ON <conds> WHEN MATCHED THEN UPDATE SET ...`.
- **Lesson:** Any Postgres update/delete that joins another table becomes a Databricks **`MERGE INTO`**. This is the single most common SCD2 porting change.

### 15. `date - date` returns an INTERVAL, not INT days
- **Symptom:** `DATATYPE_MISMATCH.BINARY_OP_DIFF_TYPES: "((date - date) > 90)" ... "INTERVAL DAY" and "INT"`.
- **Cause:** In Postgres `date - date` = integer days; in **Spark it returns an interval**, so comparing to/averaging an int fails.
- **Fix:** `a_date - b_date` → `datediff(a_date, b_date)` (int days). Found via `grep` for `.date -` / `_date -` across all models.
- **Lesson:** Never leave bare date arithmetic. `date - date` → `datediff()`; `date - N` → `date_sub(date, N)`; `date + N` → `date_add(date, N)`; `x - interval '1 day'` → `date_sub`/`add_months`/`last_day`.

### 16. Postgres `indexes=` config unsupported
- **Symptom:** N/A directly — dbt-databricks ignores/rejects the postgres-only `indexes=[...]` model config.
- **Cause:** `{{ config(materialized='table', indexes=[{'columns':['x']}]) }}` is a dbt-postgres feature. Delta clusters/optimizes differently.
- **Fix:** Removed `indexes=[...]` from the 10 gold configs (bracket-balanced removal — a naive `\[.*?\]` regex stops at the **inner** `]` and corrupts the config).
- **Lesson:** Adapter-specific configs don't carry over. Remove `indexes`; if you need clustering later, use Delta `CLUSTER BY`/`OPTIMIZE`.

### 17. Driving dbt from a script (avoiding the Git Bash 404)
- **Symptom:** Need to run dbt repeatedly to iterate, but Git Bash mangles `http_path` (entry #8).
- **Cause:** MSYS path conversion rewrites the `/sql/...` env var.
- **Fix:** Ran dbt via a tiny Python runner (`scratchpad/run_dbt.py`) that loads `.env` with `python-dotenv` and `subprocess.run(["dbt", ...], env=...)` — Python sets the env string verbatim, no MSYS. Same trick (`databricks-sql-connector` in `exec_sql.py`) ran the bronze DDL directly.
- **Lesson:** When a shell corrupts your inputs, drive the tool from Python where the strings are passed verbatim. cmd/PowerShell work too.

### 18. Incremental-only failures: `create temp table` + `to_jsonb` (audit trail)
- **Symptom:** First build passed, but a **second** run of the two delete+insert facts failed: `Syntax error at or near 'create'` (then `create temp table … to_jsonb(f)`).
- **Cause:** The `audit_change_trail` macros run as fact `pre_hook`/`post_hook` **only when `is_incremental()`** (2nd+ run). They use Postgres `create temp table`, `to_jsonb`, `jsonb_agg`, `jsonb_each_text` — none exist on Databricks. First runs skipped them, so the problem hid until the tables already existed.
- **Fix:** Gated both macros behind `{% if is_incremental() and target.type == 'postgres' %}` — Postgres keeps the audit-log feature; Databricks skips it (build stays green). Full Databricks port (temp views + `to_json`/`from_json` + map-diff) is deferred (milestone M8).
- **Lesson:** **Test the incremental path, not just the first build.** `is_incremental()`-gated SQL is invisible on run 1. Auxiliary features that can't be cheaply ported can be **gated by `target.type`** so both dialects coexist on one branch.

### 19. `TABLE_OR_VIEW_NOT_FOUND: audit.etl_batch_control`
- **Symptom:** Incremental facts failed: `audit.etl_batch_control cannot be found`.
- **Cause:** The facts' incremental watermark (`last_gold_watermark`) reads `audit.etl_batch_control`. We created the `audit` *schema* but not its *tables*.
- **Fix:** Translated `sql/audit/002_create_audit_tables.sql` to Databricks (`sql/databricks_poc/audit_tables_databricks.sql`) and created both audit tables. Empty → the watermark defaults to `1900-01-01`, so facts do a full rebuild until real batch rows exist.
- **Lesson:** A schema is not its tables. Any table a model *reads* (even in a watermark subquery) must exist. Also: when splitting a `.sql` file on `;`, **strip `--` comments first** — a `;` inside a comment (e.g. "safe to re-run; …") splits mid-comment and corrupts the next statement.

---

## SQL dialect translation cheat-sheet (Postgres → Databricks)

The mechanical core of the migration. Same patterns repeat across all 49 models.

| Postgres | Databricks | Note |
|---|---|---|
| `x::bigint` | `cast(x as bigint)` | No `::` operator in Spark SQL |
| `x::varchar(30)` / `x::text` | `cast(x as string)` | Spark has no `text`; use `string` |
| `regexp_replace(x,'\s+',' ','g')` | `regexp_replace(x,'\\s+',' ')` | Drop `'g'` (global by default); escape `\` |
| `current_timestamp::timestamp` | `current_timestamp()` | Parentheses required |
| `md5(...)::text` | `cast(md5(...) as string)` | |
| YAML `data_type: text` / `varchar(n)` | `data_type: string` | **Contracts carry dialect too** |
| `numeric(p,s)` | `decimal(p,s)` | Precision preserved |
| `encode(digest(x,'sha256'),'hex')` | `sha2(x, 256)` | pgcrypto has no equivalent |
| `date_a - date_b` | `datediff(date_a, date_b)` | Spark subtraction = interval, not int |
| `date - N` / `date + N` | `date_sub(date,N)` / `date_add(date,N)` | |
| `x - interval '1 day'` | `date_sub(x,1)` / `last_day(add_months(x,-1))` | |
| `generate_series(a,b,interval '1 day')` | `explode(sequence(a, b, interval 1 day))` | date spine |
| `to_char(d,'FMMonth'/'YYYY-MM')` | `date_format(d,'MMMM'/'yyyy-MM')` | format tokens differ |
| `date_trunc('month',d)+interval '1 month -1 day'` | `last_day(d)` | |
| `extract(dow from d)` (0=Sun) | `dayofweek(d) - 1` | Spark dayofweek is 1=Sun |
| `UPDATE t d SET ... FROM t nv WHERE ...` | `MERGE INTO t d USING t nv ON ... WHEN MATCHED THEN UPDATE SET ...` | no join-update in Spark |
| `indexes=[...]` model config | *(remove)* | postgres-only dbt config |
| Bronze DDL: `VARCHAR(n)`/`TEXT`/`JSONB`→`STRING`, `BIGSERIAL`→`BIGINT`, `INTEGER`→`INT` | | drop `DEFAULT`, `CONSTRAINT`, `COMMENT ON` |
| `initcap`, `nullif`, `coalesce`, `concat_ws`, `is distinct from`, `nulls last`, `row_number() over`, `split_part`, `left`, `right`, `||`, `sha2`, `md5` | identical | No change needed |
| incremental `merge`, SCD2 dims, `FILTER (where ...)` | supported on Delta | No change needed |

---

## Migration milestones (progress)

- [x] **M1** Sync local repo to GitHub `main`
- [x] **M2** Collect Databricks connection values (host / http_path / token)
- [x] **M3** Connect dbt → `dbt debug` passes
- [x] **M4** Port ALL 49 models + macros to Databricks dialect (SQL + contracts) ✅
- [x] **M5** Create all 21 bronze tables in Unity Catalog ✅
- [x] **M6a** Build the full project on Databricks — **49/49 PASS**, first-run AND incremental ✅
- [x] Create audit tables (`etl_batch_control`, `audit_log`) in Unity Catalog ✅
- [ ] **M6b** Load real sample data for all sources; run `dbt test`; reconcile vs Postgres
- [ ] **M7** Unity Catalog grants + a Databricks Workflow
- [ ] **M8** Port the incremental-only audit macro (temp table + jsonb) for 2nd+ runs
- [ ] **M9** Decide → paid workspace + ADLS Gen2

---

## Security follow-ups

- [ ] **Rotate the Databricks PAT** — it appeared in a screenshot during setup. Revoke + regenerate in Settings → Developer → Access tokens, then update `.env`.
- [x] `.env` and `.venv/` confirmed in `.gitignore` (token never committed).
