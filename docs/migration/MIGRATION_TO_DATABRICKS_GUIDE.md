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

## Where we are

- [x] Repo synced to GitHub, migration branch created
- [x] Local tooling (Python, venv, dbt-databricks) installed
- [x] dbt connected to Databricks (`dbt debug` passes)
- [x] **First model migrated end-to-end: `silver.customer` builds on Databricks** ✅
- [ ] Port the remaining silver + gold models (same patterns as Step 4.2–4.3)
- [ ] Load sample bronze for all sources
- [ ] Full `dbt build` + tests, reconcile against Postgres
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
