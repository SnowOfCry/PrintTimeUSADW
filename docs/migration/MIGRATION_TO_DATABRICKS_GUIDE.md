---
title: Migration to Databricks — Step-by-Step Guide
tags: [databricks, migration, dbt, guide, data-engineering, learning]
created: 2026-09-15
status: living-document
---

# Migration to Databricks — Step-by-Step Guide

A plain-language guide to migrating the **PrintTimeUSA** data warehouse from local
**Postgres** to **Azure Databricks**. Written to be reviewed by someone new to dbt
and Databricks: every step says **what** we did, **why** we did it, and **how**.

> This is a *living document*. Each new advance gets appended as its own step, so you
> can always come back and re-read the whole journey in order.

---

## Part 0 — The big picture (read this first)

### What is this project?
A **data warehouse (DW)**: a database organized for analytics, not for running the app.
It's built in three layers (the **medallion architecture**):

```
BRONZE  →  raw data, copied from the source system as-is (no cleaning)
SILVER  →  cleaned, standardized, deduplicated ("trusted") data
GOLD    →  business-ready star schema (dimensions + facts) for reports/BI
```

Data flows **bronze → silver → gold**. Each layer is a set of tables.

### What are the tools?
- **dbt** — the tool that *builds* silver and gold. You write `SELECT` statements (called
  **models**); dbt runs them in the right order and creates the tables. dbt does **not**
  move data between systems — it only transforms data already inside the warehouse. It
  stays with us permanently; it's the warehouse's transformation engine.
- **Databricks** — the cloud platform we're moving *to*. It stores tables (as **Delta**
  tables) and runs SQL on them. It replaces Postgres as the engine.
- **Unity Catalog (UC)** — Databricks' governance layer. It organizes tables and controls
  who can read what.
- **Azure** — the cloud (Microsoft) that hosts our Databricks.

### What are we actually migrating?
Two separate things — only one is really "migration":
1. **Move the data** into Databricks (one-time load + ongoing ingestion). *Not dbt's job.*
2. **Make dbt's SQL run on Databricks** instead of Postgres — this is the bulk of the work,
   because Postgres and Databricks speak slightly different SQL ("dialects").

### Why prove it on Databricks *Free Edition* first?
We don't want to pay until we know it works. **Free Edition** (not Community Edition) is
free *and* includes the real features we need — Unity Catalog, SQL Warehouse, Workflows —
so a success here means it'll work on the paid version. (Community Edition lacks all three,
so it couldn't prove anything.)

### Key concept: the three-level name
Postgres names a table as `schema.table` (two levels). Databricks/Unity Catalog uses
**three**: `catalog.schema.table` — e.g. `printtime_dw.silver.customer`.
Think of it as `drive \ folder \ file`. **Always write the full three-part name** in
hand-written SQL so you never depend on whatever "current catalog" a UI happens to point at.

---

## Part 1 — Get a clean, current starting point

### Step 1.1 — Sync the local repo to GitHub
- **What:** Made the local copy identical to `origin/main` on GitHub.
- **Why:** The local clone was **139 commits behind** GitHub. Building a migration on stale
  code means porting a warehouse that's missing its newest models. Always start from the
  real, current code.
- **How:**
  ```bash
  git fetch origin
  git checkout main
  git pull --ff-only origin main
  ```
  `--ff-only` = "only fast-forward, refuse anything messy" — a safety guard. We confirmed
  `origin/main...main` showed `0 0` (identical) afterward.

### Step 1.2 — Create a migration branch
- **What:** Made a new branch `migrate/databricks` off the synced `main`.
- **Why:** You never do risky work directly on `main`. A branch isolates the migration so
  `main` stays a known-good copy you can always compare against or fall back to.
- **How:**
  ```bash
  git checkout -b migrate/databricks
  ```

---

## Part 2 — Set up the local tools

### Step 2.1 — Install Python
- **What:** Installed Python 3.12.
- **Why:** dbt is a Python program. The project normally runs in Docker, so this machine had
  no local Python — `pip`/`python` weren't recognized.
- **How:** `winget install -e --id Python.Python.3.12`, then a **new** terminal (PATH only
  updates in new shells).

### Step 2.2 — Virtual environment (venv)
- **What:** Created an isolated Python environment `.venv`.
- **Why:** A venv keeps this project's libraries separate from the rest of the system, so
  versions never clash between projects. Standard professional practice.
- **How:**
  ```bash
  python -m venv .venv
  .venv\Scripts\activate     # prompt shows (.venv) when active
  ```
  *(Tip we learned: activate the venv **before** `pip install`, or packages land in global
  Python instead.)*

### Step 2.3 — Install the Databricks adapter for dbt
- **What:** Installed `dbt-databricks` (the plugin that lets dbt talk to Databricks).
- **Why:** dbt needs an "adapter" per database. We had `dbt-postgres`; Databricks needs
  `dbt-databricks`.
- **How:** `pip install dbt-databricks` → verified with `dbt --version` (lists `databricks`
  under Plugins).

---

## Part 3 — Connect dbt to Databricks

### Step 3.1 — Collect three connection values (in the Databricks UI)
- **What:** Got the **Host**, **HTTP path**, and a **token**.
- **Why:** dbt connects to a Databricks **SQL Warehouse** (the compute that runs SQL) and
  needs to know where it is (host + http_path) and how to authenticate (token).
- **How:**
  - **Host** — from the browser URL: `dbc-xxxx.cloud.databricks.com`.
  - **HTTP path** — SQL → SQL Warehouses → your warehouse → **Connection details**.
  - **Token** — avatar → Settings → Developer → Access tokens → Generate.

### Step 3.2 — Store secrets in `.env`
- **What:** Created a git-ignored `.env` file with the five values.
- **Why:** Secrets (like the token) must never be committed to git. `.env` is a local,
  ignored file. (Note: `.env.example` is a committed *template* — don't put real secrets there.)
- **How:** In VS Code, created a file named exactly `.env`:
  ```
  DBRICKS_HOST=dbc-xxxx.cloud.databricks.com
  DBRICKS_HTTP_PATH=/sql/1.0/warehouses/xxxx
  DBRICKS_TOKEN=dapi...
  DBT_CATALOG=printtime_dw
  DBT_SCHEMA=bronze
  ```

### Step 3.3 — Add a `databricks` target to `profiles.yml`
- **What:** Added a third connection block (alongside the existing postgres `dev`/`prod`).
- **Why:** `profiles.yml` tells dbt *how* to connect. We add a new "target" we opt into with
  `--target databricks`, leaving the postgres ones untouched so `main` still works.
- **How:** Added:
  ```yaml
  databricks:
    type: databricks
    catalog:   "{{ env_var('DBT_CATALOG', 'printtime_dw') }}"   # the new 3rd level (UC)
    schema:    "{{ env_var('DBT_SCHEMA', 'silver') }}"
    host:      "{{ env_var('DBRICKS_HOST') }}"
    http_path: "{{ env_var('DBRICKS_HTTP_PATH') }}"
    token:     "{{ env_var('DBRICKS_TOKEN') }}"
    threads:   4
  ```
  Note `catalog:` — Postgres profiles don't have it; Databricks does (three-level names).

### Step 3.4 — Test the connection
- **What:** Ran `dbt debug` and got **All checks passed**.
- **Why:** Confirms dbt can actually reach and authenticate to the warehouse before we try
  to build anything.
- **How:**
  ```bash
  dotenv run -- dbt debug --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw
  ```
  `dotenv run --` loads `.env` into the environment (dbt does **not** read `.env` on its own).

---

## Part 4 — Migrate the first model (a "thin vertical slice")

### Why a thin slice?
Instead of porting all 49 models at once and debugging blind, we take **one table all the
way through** first: sample data → port the model → run it → see it work. This surfaces the
real dialect problems on one model, gives a working template, and turns the rest into
repetition. We chose **`customer`** because it uses most of the tricky syntax.

### Step 4.1 — Seed sample bronze data
- **What:** Created `printtime_dw.bronze.oltp_customer` with 6 hand-made rows.
- **Why:** The source Postgres is offline (that's *why* we're migrating). silver.customer
  reads from bronze.oltp_customer, so we need some bronze data to transform. The rows were
  designed to test the cleaning logic (messy whitespace, mixed-case email, a bad status, a
  duplicate id).
- **How:** Ran [`sql/databricks_poc/bronze_oltp_customer_sample.sql`](../../sql/databricks_poc/bronze_oltp_customer_sample.sql)
  in the Databricks SQL editor. (Postgres types were translated: `VARCHAR(n)`→`STRING`,
  `JSONB`→`STRING`, etc.)

### Step 4.2 — Port the SQL dialect (model + shared macro)
- **What:** Rewrote `silver/customer.sql` and the shared `silver_lineage_and_metadata` macro
  from Postgres SQL to Databricks SQL.
- **Why:** Databricks (Spark SQL) doesn't understand some Postgres syntax. The macro is used
  by **all 20 silver models**, so porting it once fixes them all.
- **How — the patterns (this is the core skill):**

  | Postgres | Databricks | Why |
  |---|---|---|
  | `x::bigint` | `cast(x as bigint)` | Spark has no `::` cast operator |
  | `x::varchar(30)` / `x::text` | `cast(x as string)` | Spark has no `text`; use `string` |
  | `regexp_replace(x,'\s+',' ','g')` | `regexp_replace(x,'\\s+',' ')` | Spark regex is global already; drop `'g'`, escape `\` |
  | `current_timestamp::timestamp` | `current_timestamp()` | needs parentheses |
  | `md5(...)::text` | `cast(md5(...) as string)` | same cast rule |

  Left unchanged (Databricks supports these identically): `initcap`, `nullif`, `coalesce`,
  `concat_ws`, `is distinct from`, `nulls last`, `row_number() over (...)`, and the
  incremental `merge` config.

### Step 4.3 — Port the YAML contract
- **What:** Changed `data_type: text` → `data_type: string` (43 places) in
  `models/silver/_silver_models.yml`.
- **Why (important surprise):** dbt models here have **enforced contracts** — the YAML
  declares each column's exact type, and dbt checks it. Those declarations were Postgres
  types. `text` isn't a Databricks type, so dbt's internal schema-check query failed with
  `Unsupported data type "TEXT"`. **Dialect hides in YAML, not just SQL.**
- **How:** Find-and-replaced `data_type: text` → `data_type: string`. (`varchar(n)` is
  accepted by Databricks, so only `text` strictly needed changing.)

### Step 4.4 — Build the model
- **What:** Ran the model; `silver.customer` built successfully (`PASS=1`).
- **Why:** Proves the whole slice works end-to-end on Databricks.
- **How:**
  ```bash
  dotenv run -- dbt run --select customer --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{silver_batch_id: 1}"
  ```
  - `--select customer` = build only this model.
  - `--vars "{silver_batch_id: 1}"` = required, because a project macro (`require_batch_id`)
    refuses to run without a batch id (so data lineage is never faked). The orchestrator
    supplies this in production.

> **Gotchas we hit here** (full detail in [ERROR_AND_FIX_LOG.md](ERROR_AND_FIX_LOG.md)):
> - `text` type in the YAML contract → change to `string`.
> - Running dbt from **Git Bash** corrupted the `http_path` (`/sql/...` → `C:/Program Files/Git/sql/...`)
>   causing 404s. **Run dbt from cmd/PowerShell, not Git Bash.**
> - The SQL Warehouse auto-stops; start it in the UI before running.

---

## Part 5 — Port the whole warehouse and build it

With the pattern proven on one model, we scaled to all 49 — but automated the mechanical
parts instead of hand-editing, and hit several *new* dialect issues that only one model
(`customer`) hadn't exercised.

### Step 5.1 — Automate the cast port
- **What:** Wrote a Python script that converts `expr::type` → `cast(expr as type)` across
  every model + macro, plus the regex/`now()` fixes.
- **Why:** 48 files with hundreds of casts is too slow and risky by hand. A parser that
  understands operand boundaries (balanced parens, `case…end`) does it reliably.
- **How:** `scratchpad/port_pg_to_databricks.py` (kept for reference). It walks left from
  each `::` to find the operand, then rewrites it. After running, we **grepped the output**
  for constructs it can't handle and fixed those by hand — see 5.3.
  > Two parser bugs we caught: paramless casts ate trailing spaces (`)as`), and
  > `count(*) FILTER (...)::int` got mangled. Always verify automated edits.

### Step 5.2 — Rewrite Postgres-only date logic (gold)
- **What:** Hand-rewrote `gold/dim_date.sql` and `gold/fact_customer_behavior_snapshot.sql`.
- **Why:** These use Postgres date functions with no 1:1 Spark cast.
- **How (the key swaps):**
  - `generate_series(a,b,interval '1 day')` → `explode(sequence(a, b, interval 1 day))`
  - `to_char(d,'FMMonth')` → `date_format(d,'MMMM')`; `'YYYY-MM'` → `'yyyy-MM'`
  - `date_trunc('month',d)+interval '1 month -1 day'` → `last_day(d)`
  - `extract(dow from d)` (Postgres 0=Sun) → `dayofweek(d) - 1` (Spark 1=Sun)
  - `date + n` → `date_add(d,n)`; `x - interval '1 day'` → `last_day(add_months(...,-1))`

### Step 5.3 — Fix what the build surfaced (iterate)
We built **layer by layer** and fixed each error the engine reported. Every fix is logged in
[ERROR_AND_FIX_LOG.md](ERROR_AND_FIX_LOG.md) (entries 12–17). The new ones beyond `customer`:
- **`digest()` unresolved** → SCD2 dims hashed with `encode(digest(x,'sha256'),'hex')`;
  became `sha2(x, 256)`.
- **`UPDATE ... FROM` syntax error** → SCD2 version-close post-hooks are Postgres join-updates;
  Spark needs **`MERGE INTO`**. Rewrote all 6.
- **`date - date` type mismatch** → Spark returns an interval, not int days; use `datediff()`.
- **`indexes=[...]` config** → postgres-only; removed from 10 gold models.

### Step 5.4 — Create the bronze tables in Databricks
- **What:** Created all 21 bronze source tables in Unity Catalog.
- **Why:** silver models read from bronze; the tables must exist. The source OLTP is offline,
  so we build the tables empty (a couple seeded with sample rows) — enough to prove the whole
  pipeline runs.
- **How:** Translated the Postgres bronze DDL to Databricks types
  (`sql/databricks_poc/bronze_tables_databricks.sql`: `VARCHAR/TEXT/JSONB`→`STRING`,
  `BIGSERIAL`→`BIGINT`, dropped `DEFAULT`/`CONSTRAINT`/`COMMENT`), then ran it against the
  warehouse.

### Step 5.5 — Build silver, then gold
- **What:** Built both layers on Databricks. Result: **silver 21/21 PASS, gold 28/28 PASS**.
- **How:**
  ```bash
  # silver
  dotenv run -- dbt run --select silver --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{silver_batch_id: 1}"
  # gold (facts need a per-target batch-id map; dims share 'gold.dimensions')
  dotenv run -- dbt run --select gold --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{gold_batch_ids: {gold.dimensions: 1, gold.fact_customer_behavior_snapshot: 1, gold.fact_payments: 1, gold.fact_retail_sales: 1}}"
  ```
- **Result:** **The entire warehouse — all 49 models — now builds natively on Databricks.** 🎉

---

## Part 6 — Governance: Unity Catalog grants (replaces the Postgres roles)

Translated `sql/security/001_create_roles.sql` (Postgres roles) into Unity Catalog
grants — same least-privilege intent (ADR-013), enforced by the catalog.

### Step 6.1 — Create the groups
- **What:** Created 3 workspace groups: `pt_ingestion`, `pt_dbt`, `pt_bi_reader`.
- **Why:** UC grants are given to *principals* (groups/users), the way Postgres granted
  to roles.
- **How:** Settings → Identity and access → Groups → Add group. Entitlements:
  all three get **Databricks SQL access**; `pt_ingestion`/`pt_dbt` also get **Workspace
  access**; `pt_bi_reader` does **not** (least privilege). None get **Admin**.
  > Entitlements only decide login/compute access — they are NOT data security. The
  > data protection is the grants in 6.2.

### Step 6.2 — Grant data access
- **What:** Ran `sql/security/002_unity_catalog_grants.sql`.
- **Why:** This is the actual security model — who can read/write which schema.
- **How (the mapping):**
  | Group | Grant |
  |---|---|
  | pt_ingestion | `USE SCHEMA, SELECT, MODIFY` on bronze, audit |
  | pt_dbt | `SELECT` on bronze; `SELECT, MODIFY` on audit; `ALL PRIVILEGES` on silver, gold |
  | pt_bi_reader | `USE SCHEMA, SELECT` on **gold only** |
- **Two UC facts that differ from Postgres:**
  - Privileges are **inherited** — `GRANT SELECT ON SCHEMA` covers all current *and future*
    tables. No per-table grants, no `ALTER DEFAULT PRIVILEGES`.
  - Write is one privilege, **`MODIFY`** (no separate INSERT/UPDATE). Read is `SELECT`.

### Step 6.3 — Verify the PII guarantee
- **What:** Confirmed `pt_bi_reader` can read gold but nothing on silver.
- **How:**
  ```sql
  SHOW GRANTS `pt_bi_reader` ON SCHEMA printtime_dw.gold;    -- returns SELECT/USE SCHEMA
  SHOW GRANTS `pt_bi_reader` ON SCHEMA printtime_dw.silver;  -- returns ZERO rows
  ```
- **Why it matters:** UC denies by default, so the empty silver result *is* the ADR-013
  guarantee — BI structurally cannot read `silver.customer`'s email/phone. Enforcement,
  not policy.

---

## Part 7 — Orchestration: a Databricks Workflow (replaces Airflow)

Ran dbt *inside* Databricks on a schedule — the native replacement for the Airflow
`printtime_elt_pipeline` DAG. This is where dbt finally appears **in** Databricks
(vs. running from your laptop).

### Scope
The Airflow DAG had two halves: Python OLTP ingestion, and the dbt run/test steps.
The OLTP is offline, so this Workflow orchestrates **the dbt half** (silver → gold →
test). Real ingestion tasks would be added upstream when a source exists.

### Step 7.1 — Connect GitHub to Databricks
- **What:** Linked the GitHub account so the job can fetch the repo.
- **How:** Settings → Linked accounts / Git integration → GitHub → authorize (OAuth or a
  PAT with `repo` scope).

### Step 7.2 — Create the Job + dbt task
- **What:** One job `printtime_elt_databricks` with a single **dbt** task
  `dbt_build_and_test`.
- **How:** Workflows → Create job → task type **dbt**:
  - Source: **Git**, repo URL, branch `migrate/databricks`
  - dbt project directory: `dbt/printtime_dw`
  - SQL warehouse: the serverless warehouse
  - Catalog `printtime_dw`, Schema `silver`
  - dbt commands (run in order; `dbt test` at the end **gates** the run):
    ```
    dbt run --select silver --vars '{silver_batch_id: 1}'
    dbt run --select gold --vars '{gold_batch_ids: {gold.dimensions: 1, gold.fact_customer_behavior_snapshot: 1, gold.fact_payments: 1, gold.fact_retail_sales: 1}}'
    dbt test
    ```
- **Key:** do NOT add `--target` / `--profiles-dir` / `--project-dir` — the managed dbt
  task **auto-generates its own `profiles.yml`** from the warehouse + catalog + schema, so
  no token is needed here (the job uses its own identity). The repo's `profiles.yml`
  (env-var based) is only for local runs.

### Step 7.3 — Run, schedule, alert
- **Run now** → **Succeeded**; the dbt Output shows `PASS=49` (runs) and `PASS=182 ERROR=0`
  (tests). Verified the warehouse still reconciles (gold = silver line total, diff 0).
- **Schedule:** Schedules & Triggers → Add trigger → Scheduled (e.g. daily). Toggle off
  when not demoing to save Free-Edition capacity.
- **Alert:** Notifications → add email on Failure (the Airflow `alert_on_failure` equivalent).

### Known cosmetic noise (not errors)
The run log shows two `PermissionError`s from Databricks' own wrapper — one writing the
generated `profiles.yml` to a temp dir, one in `shutil.rmtree` cleaning up the cloned repo
*after* the run. Both are Free-Edition serverless quirks; the job Succeeds and the dbt
Output shows `ERROR=0`. Nothing in the project to fix.

### Advanced follow-up (optional)
The Workflow config lives in Databricks, not Git. To version it, export it as a
**Databricks Asset Bundle** (`databricks.yml` + job YAML) and commit it — then the job
itself is code-reviewed and reproducible.

---

## Where we are

- [x] Repo synced to GitHub, migration branch created
- [x] Local tooling (Python, venv, dbt-databricks) installed
- [x] dbt connected to Databricks (`dbt debug` passes)
- [x] First model migrated end-to-end: `silver.customer`
- [x] **ALL 49 models ported + building on Databricks — 49/49 PASS, first-run AND incremental** ✅
- [x] All 21 bronze tables + 2 audit tables created in Unity Catalog
- [x] **Loaded synthetic data + `dbt test` 182/182 PASS + gold reconciles exactly to silver** ✅
- [x] Ported `tests/` singular tests to Databricks dialect
- [x] **Unity Catalog governance: 3 groups + grants; PII guarantee verified (bi_reader has no silver access)** ✅
- [x] **Databricks Workflow: dbt runs in Databricks on a schedule (silver→gold→test), 182/182 green, alerts on failure** ✅
- [ ] Port the incremental-only audit change-trail macro (temp table + jsonb) for 2nd+ runs (gated to postgres for now)
- [ ] Paid workspace + ADLS Gen2 (leave Free Edition) · rotate the PAT
- [ ] Unity Catalog grants + a Databricks Workflow
- [ ] Decide → paid Azure workspace + ADLS Gen2

---

## Quick reference — commands we use

```bash
# Always run dbt from cmd/PowerShell (not Git Bash), from the repo root:

# test the connection
dotenv run -- dbt debug --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw

# build one model
dotenv run -- dbt run --select customer --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{silver_batch_id: 1}"

# build a whole layer (later)
dotenv run -- dbt run --select silver --target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{silver_batch_id: 1}"
```
