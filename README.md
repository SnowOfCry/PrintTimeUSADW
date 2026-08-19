# PrintTimeUSA Data Warehouse

> ### 📌 Portfolio project — public version
> Published **only as a public/portfolio version for recruiters and hiring managers to review my
> work**. **"PrintTimeUSA" is a fictional retail print shop and every record is synthetically
> generated** — no real customer, employee, financial, or PII data appears anywhere in this
> repository. This portfolio version is shared **with the knowledge and approval of the project's
> manager and CEO**.

A production-shaped, fully containerized **ELT data warehouse** for PrintTimeUSA — a retail
print shop in Modesto, CA. It ingests operational data from an OLTP source into a raw **bronze**
layer, refines it into a clean, contract-enforced **silver** layer with dbt, and serves a
Kimball **gold** star schema for analytics — orchestrated by Apache Airflow, running entirely
in Docker.

> Clone the repo, copy `.env.example` to `.env`, and run `docker compose up -d`. No local
> language runtimes required — everything runs in containers.

---

## Highlights

- **Medallion architecture** (bronze → silver → gold) with an `audit` schema for ETL batch
  control and lineage.
- **ELT, not ETL** — Python owns Extract + Load only; every transformation is SQL in the
  warehouse via **dbt Core**, so raw history is always preserved and logic is re-runnable.
- **Contract-enforced silver layer — 20/20 models complete.** Every model is an incremental,
  hash-gated merge with an enforced dbt contract (types, `NOT NULL`, primary key), deterministic
  deduplication, and ADR-005 cleaning standards.
- **Complete gold star schema — 14/14 objects.** 8 dimensions (6 SCD Type 2 with full version
  history), 3 facts, and 3 role-playing date views. Every fact reconciles to silver **to the
  cent**, and the whole warehouse passes **195/195 dbt tests**.
- **Least-privilege security** — three purpose-scoped database roles (ingestion / dbt / BI
  reader) instead of a shared superuser ([ADR-019](docs/adr/019-least-privilege-database-roles.md)).
- **Independently audited** — three external Data-Warehouse audits ([`docs/audit/`](docs/audit/)),
  every finding **remediated or consciously accepted (zero open)** and traced in the
  [fix log](docs/fix/fix_log.md).
- **API ingestion** — beyond the OLTP source, an HTTP **FRED** (Federal Reserve) source lands
  CPI/PPI into bronze (secrets, retry, incremental), powering nominal-vs-**real** revenue and
  margin-vs-input-cost analyses ([ADR-020](docs/adr/020-external-fred-macro-source.md)).
- **Design decided in the open** — 20 Architecture Decision Records ([`docs/adr/`](docs/adr/))
  capture every significant choice, its alternatives, and its consequences.
- **Specification-first** — hand-written DDL specs, per-column data dictionaries, and
  source-to-target mappings are the source of truth; dbt honors them.

## Tech stack

| Layer | Technology |
|---|---|
| Warehouse database | PostgreSQL 16 |
| Transformation | dbt Core 1.8 + dbt-postgres (model contracts, incremental merge) |
| Ingestion (Extract + Load) | Python 3.11 (pandas, SQLAlchemy) |
| Orchestration | Apache Airflow 2.9 |
| Database GUI | pgAdmin 4 |
| Security | Least-privilege PostgreSQL roles — `pt_ingestion` / `pt_dbt` / `pt_bi_reader` (ADR-019) |
| Code quality | ruff, mypy, pytest + 195 dbt data tests (CI on every push) |
| Runtime | Docker + Docker Compose |

---

## Table of Contents

1. [Architecture](#architecture)
2. [Project Status](#project-status)
3. [Repository Structure](#repository-structure)
4. [Getting Started](#getting-started)
5. [Docker Services](#docker-services)
6. [Service URLs & Credentials](#service-urls--credentials)
7. [The dbt Transformation Layer](#the-dbt-transformation-layer)
8. [Python Ingestion Layer](#python-ingestion-layer)
9. [Orchestration (Airflow DAG)](#orchestration-airflow-dag)
10. [Audit, Batches & Watermarks](#audit-batches--watermarks)
11. [Documentation](#documentation)
12. [Development Workflow](#development-workflow)
13. [Roadmap](#roadmap)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AIRFLOW (Orchestration)                        │
│                                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐    ┌──────────┐  │
│  │ Extract  │──▶ │  Load        │──▶ │  Transform    │──▶ │  Test    │  │
│  │ (Python) │    │  (Python)    │    │  (dbt)        │    │  (dbt)   │  │
│  └──────────┘    └──────────────┘    └───────────────┘    └──────────┘  │
│       │                 │                    │                          │
│  OLTP source       bronze schema     silver → gold schemas              │
└─────────────────────────────────────────────────────────────────────────┘

PostgreSQL schemas
──────────────────
bronze   Raw source rows, append-only (Python writes here)
silver   Clean, typed, deduplicated — one current row per business key (dbt)
gold     Kimball star schema: conformed dimensions + facts (dbt)
audit    ETL batch control, incremental watermarks, row-level change trail
```

- **Extract** — Python reads from the OLTP source, using per-table watermarks for incremental
  loads.
- **Load** — Python appends raw rows into `bronze` with zero business transformation.
- **Transform** — dbt cleans `bronze` into `silver` (incremental hash-gated merge), then builds
  the `gold` star schema.
- **Orchestrate** — an Airflow DAG sequences extract → load → silver → gold → tests.
- **Govern** — `audit.etl_batch_control` records every batch (run stats + watermarks);
  `audit.audit_log` holds the row-level change trail.

### Why ELT instead of ETL

| Concern | ETL | ELT (this project) |
|---|---|---|
| Where transforms happen | Separate tool, before load | In the warehouse, in SQL (dbt) |
| Raw history | Often discarded | Always retained in bronze |
| Re-processing | Must re-extract to change logic | Re-run dbt against existing bronze |
| Language coupling | Two languages intertwined | Python extracts only; SQL owns business logic |

See [ADR-003: ELT over ETL](docs/adr/003-elt-over-etl.md) and
[ADR-001: Adopt a medallion architecture](docs/adr/001-adopt-medallion-architecture.md).

---

## Project Status

| Layer | Status |
|---|---|
| **Bronze** (20 source tables) | ✅ Ingested via Python (append-only) |
| **Silver** (20 models) | ✅ **Complete** — contract-enforced incremental merge — released as `v0.1.0-silver` |
| **Gold** (Kimball star schema, 14 objects) | ✅ **Complete** — 8 dims (6 SCD2) + 3 facts + 3 date views — released as `v0.2.0-gold` |
| **Audit** (batch control + lineage) | ✅ In place |
| **Orchestration** (Airflow DAG) | ✅ **Wired + scheduled** — bronze → silver → gold → tests, real batch IDs, genuinely incremental fact loads; **runs daily** (ELT 08:00 PT; backup + restore-verify 10:00 PT) |
| **API source** (FRED macro indicators) | ✅ CPI/PPI → real-terms revenue + margin-vs-cost, DQ-tested ([ADR-020](docs/adr/020-external-fred-macro-source.md)) |
| **Security** (least-privilege RBAC) | ✅ Three scoped roles — `pt_ingestion` / `pt_dbt` / `pt_bi_reader` (ADR-019) |
| **Governance** (20 ADRs, dictionaries, mappings, fix log) | ✅ Complete |
| **External audits** (3 independent reviews) | ✅ **Every finding remediated or consciously accepted — zero open** — see [`docs/audit/`](docs/audit/) + [fix log](docs/fix/fix_log.md) |

**Warehouse-wide: `dbt build --select silver gold` passes all 195 dbt tests.**
The facts reconcile exactly to silver — retail sales, payments, and customer lifetime value all
match to the cent, with zero unresolved dimension keys. See the
[gold star schema](docs/architecture/gold_star_schema.md) for the dimensional model.

---

## Repository Structure

```
PrintTimeUSADW/
├── docker/                          Docker build contexts (postgres, airflow, dbt)
├── airflow/
│   └── dags/                            ELT pipeline + backup/restore-verify DAGs
├── ingestion/                       Python Extract + Load (no business logic)
│   ├── extract/  load/  utils/  config/  main.py
├── dbt/printtime_dw/                dbt project
│   ├── dbt_project.yml  profiles.yml
│   ├── macros/generate_schema_name.sql
│   └── models/
│       ├── bronze/_bronze_sources.yml      source declarations (oltp_*, ref_*)
│       ├── silver/                         20 models + _silver_models.yml (contracts)
│       └── gold/                           8 dims + 3 facts + 3 date views + _gold_models.yml
├── sql/                             Authoritative DDL specs (bronze/silver/gold/audit)
├── docs/                            ADRs, data dictionaries, mappings, load strategies, dbt guide
├── tests/                           unit / integration / data_quality
├── scripts/                         start.sh · stop.sh · reset.sh · healthcheck.sh
├── .github/workflows/ci.yml
├── docker-compose.yml
└── .env.example
```

---

## Getting Started

### Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- Git

### 1. Clone and configure
```bash
git clone https://github.com/<your-org>/PrintTimeUSADW.git
cd PrintTimeUSADW
cp .env.example .env        # then edit .env and set your passwords — never commit it
```

Generate an Airflow Fernet key and paste it into `.env` as `AIRFLOW_FERNET_KEY`:
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### 2. Start the stack
```bash
bash scripts/start.sh          # or: docker compose build && docker compose up -d
```

### 3. Verify
```bash
bash scripts/healthcheck.sh
docker compose run --rm dbt dbt debug          # expect: "All checks passed!"
```

### Stopping and resetting
```bash
bash scripts/stop.sh           # stop, preserving data (named volumes)
bash scripts/reset.sh          # DESTRUCTIVE — removes all data volumes
```

---

## Docker Services

| Service | Image | Host Port | Purpose |
|---|---|---|---|
| `postgres` | postgres:16 (custom) | **5433** → 5432 | Warehouse database |
| `pgadmin` | dpage/pgadmin4 | 5050 | PostgreSQL GUI |
| `airflow-webserver` | Airflow 2.9 (custom) | 8080 | Airflow UI |
| `airflow-scheduler` | Airflow 2.9 (custom) | — | DAG scheduling |
| `airflow-init` | Airflow 2.9 (custom) | — | One-time DB migration + admin user |
| `dbt` | Python 3.11 (custom) | — | dbt Core + dbt-postgres (run ad-hoc) |

All services share one Docker bridge network, `elt_network`. Inside the network, containers
reach Postgres at `postgres:5432`; from your host, use `localhost:5433`.

---

## Service URLs & Credentials

| Service | URL | Default credential (from `.env.example`) |
|---|---|---|
| pgAdmin | http://localhost:5050 | `admin@printtime.com` / `changeme_pgadmin` |
| Airflow | http://localhost:8080 | `admin` / `changeme_admin` |
| PostgreSQL | `localhost:5433` | `warehouse_user` / `changeme_warehouse` |

> These are development defaults. **Change every password before using real data.**
> `PGADMIN_EMAIL` must be a real email format (a `.local`/internal domain is rejected by
> pgAdmin's login validator).

**Connect pgAdmin to Postgres:** Servers → Register → Server → Connection tab →
Host `postgres`, Port `5432` (in-network), DB `printtime_dw`, user/password from `.env`.
(Use `localhost` / `5433` only from a client running on your host.)

---

## The dbt Transformation Layer

Location: [`dbt/printtime_dw/`](dbt/printtime_dw/)

| Layer | Schema | What dbt does |
|---|---|---|
| Bronze | `bronze` | Source declarations (`oltp_*`, `ref_*`) + optional freshness checks |
| Silver | `silver` | Clean, cast, normalize, deduplicate → one current row per key (incremental merge) |
| Gold | `gold` | Kimball dimensions (`dim_*`) and facts (`fact_*`) — SCD2 + per-grain loads |

Every silver model shares one spec-compliant shape:

- **Incremental merge** keyed on the business key, with a watermark on `bronze_batch_id`
  ([ADR-006](docs/adr/006-silver-incremental-merge.md)).
- **Deterministic dedup** — `ROW_NUMBER()` over the standardized freshness order.
- **Change-detection hash** (`silver_row_hash`) so the merge fires only on genuine change.
- **Enforced contract** — types, `NOT NULL`s, and the primary key
  ([`models/silver/_silver_models.yml`](dbt/printtime_dw/models/silver/_silver_models.yml)).
- **ADR-005 cleaning** — casting, normalization, lowercase status vocabularies, derived flags.

The gold layer builds the star schema on top ([diagram](docs/architecture/gold_star_schema.md)):

- **SCD Type 2 dimensions** ([ADR-015](docs/adr/015-gold-scd2-dbt-implementation.md)) — custom
  incremental `append` models: a changed entity gets a *new version row* (`row_version + 1`) and
  a post-hook closes the prior one (`is_current = false`). Matching is on the durable source id,
  change detection on a SHA-256 `record_hash`, and surrogate keys are dbt-managed integers that
  stay stable across runs.
- **Facts at their natural grain** — `fact_retail_sales` reloads by invoice, `fact_payments`
  resolves its refund chain in-model ([ADR-009](docs/adr/009-facts-carry-no-source-business-keys.md)),
  and the behavior snapshot appends one immutable customer snapshot per month-end.
- **`-1` "Not Provided" members** ([ADR-011](docs/adr/011-unknown-members-and-unenforced-fks.md))
  in every dimension, so a failed lookup stays countable instead of becoming a NULL join.
- **Role-playing date views** ([ADR-010](docs/adr/010-role-playing-date-views.md)) — one
  conformed `dim_date`, re-labelled per role by a single macro.

Common commands (dbt runs in its container):
```bash
docker compose run --rm dbt dbt debug                         # verify connection
docker compose run --rm dbt dbt build  --select silver        # build + test all silver models
docker compose run --rm dbt dbt run    --select state         # one model
docker compose run --rm dbt dbt run    --select silver --full-refresh
```

New to the project? See the from-scratch build guide:
[`docs/dbt/PrintTimeUSA_dbt_Build_Guide.docx`](docs/dbt/PrintTimeUSA_dbt_Build_Guide.docx),
and the running decision log [`docs/dbt/dbt_decisions.md`](docs/dbt/dbt_decisions.md).

---

## Python Ingestion Layer

Location: [`ingestion/`](ingestion/)

Python is responsible **only** for Extract + Load:
- connect to the OLTP source and extract raw rows (incremental via watermarks),
- append raw rows into `bronze` with zero business transformation,
- record batch + watermark state in `audit.etl_batch_control`.

It does **not** clean data or build models — that is dbt's job (see
[ADR-003](docs/adr/003-elt-over-etl.md)).

| File | Purpose |
|---|---|
| `ingestion/extract/oltp_extractor.py` | Read rows from the OLTP source |
| `ingestion/load/bronze_loader.py` | Append raw rows to `bronze`, stamping metadata |
| `ingestion/utils/database.py` | Connection helpers (OLTP + warehouse) |
| `ingestion/utils/batch_control.py` | Start/complete/fail batch records in `audit` |
| `ingestion/utils/watermark.py` | Resolve the last successful watermark per table |
| `ingestion/config/ingestion_config.yml` | Source → bronze table configuration |

---

## Orchestration (Airflow DAG)

File: [`airflow/dags/printtime_elt_pipeline.py`](airflow/dags/printtime_elt_pipeline.py)

```
start_pipeline
  → ingest_oltp_to_bronze     Python — extract each configured table → bronze
  → start_silver_batch        Python — open a batch in audit.etl_batch_control
  → run_dbt_silver            dbt run --select silver --vars silver_batch_id=<key>
  → complete_silver_batch     Python — mark succeeded (+ rows from run_results.json)
  → start_gold_batches        Python — one batch per gold target
  → run_dbt_gold              dbt run --select gold
  → complete_gold_batches     Python — mark succeeded → advances the fact watermark
  → run_dbt_tests             dbt test (fails the DAG on any broken test)
end_pipeline
fail_open_batches             Python — on failure only: closes stranded 'running' batches
```

**Batch control is what makes the loads incremental.** Silver rows are stamped with the real
`silver_batch_id` from `audit.etl_batch_control`, and the gold facts detect "what changed" by
comparing `silver_updated_at_timestamp` against the last **succeeded** gold batch for their
target — so completing those batches here is what turns the facts from full reloads into
incremental ones. `fail_open_batches` (trigger rule `ONE_FAILED`) closes any batch a crashed run
left open, so a later fix can't silently advance the watermark.

dbt runs inside the Airflow image (`dbt-core`/`dbt-postgres` pinned identically to
`docker/dbt/requirements.txt`), with the project mounted at `/dbt/printtime_dw`. dbt writes its
logs and artifacts to `/opt/airflow/dbt_artifacts` so orchestrated runs never collide with
ad-hoc ones in the dbt container.

**Runs daily at 08:00 America/Los_Angeles** (a "data-ready-by-8am" SLA; `catchup=False`), and is
also triggerable manually from the Airflow UI. A companion DAG, **`printtime_backup_pipeline`**,
runs at **10:00** — `pg_dump` the warehouse, then restore the fresh dump into a throwaway DB and
reconcile row counts (automated restore-verification, ADR-018).

Verified end to end: a `state_name` change in the OLTP source flowed to bronze → silver (1 row
rewritten, stamped with a real batch id, the other two untouched) → gold (every California store
and customer versioned via SCD2, facts correctly reloading 0 rows), and a following run with no
source changes loaded **0** fact rows instead of 447k.

---

## Audit, Batches & Watermarks

The `audit` schema is the single source of ETL truth
([ADR-008](docs/adr/008-consolidate-etl-control-into-audit-schema.md)).

```sql
-- Recent ETL batches
SELECT source_system, target_table, load_type, batch_status,
       rows_extracted, rows_inserted, rows_updated,
       batch_start_timestamp, batch_end_timestamp, error_message
FROM   audit.etl_batch_control
ORDER  BY batch_start_timestamp DESC
LIMIT  20;

-- Latest successful watermark per target table
SELECT DISTINCT ON (target_table)
       source_system, target_table, watermark_column,
       watermark_value_end AS last_watermark, batch_end_timestamp
FROM   audit.etl_batch_control
WHERE  batch_status = 'succeeded'
ORDER  BY target_table, batch_end_timestamp DESC;
```

---

## Documentation

The `docs/` tree is a first-class part of this project:

| Area | Location |
|---|---|
| **Concept guides** (CDC · SCD · Governance & Audit) | [`docs/guides/`](docs/guides/) — [CDC](docs/guides/cdc.md) · [SCD](docs/guides/scd.md) · [Governance & Audit](docs/guides/governance-and-audit.md) |
| **Architecture Decision Records** (001–020) | [`docs/adr/`](docs/adr/) — start at [the index](docs/adr/README.md) |
| **External audit reports** (3 independent DW reviews) | [`docs/audit/`](docs/audit/) |
| **Fix log** (root causes + the rules they generalize to) | [`docs/fix/fix_log.md`](docs/fix/fix_log.md) |
| **Gold star schema** (ER diagram + querying guide) | [`docs/architecture/gold_star_schema.md`](docs/architecture/gold_star_schema.md) |
| **BI layer** (Power BI DAX measures + build guide) | [`docs/bi/`](docs/bi/) — serving views in `models/gold/bi/` |
| **Data dictionaries** (bronze / silver / gold / audit) | [`docs/data_dictionary/`](docs/data_dictionary/) |
| **Source-to-target mappings** | [`docs/source_to_dw_mapping/`](docs/source_to_dw_mapping/) |
| **Load strategies** (bronze / silver / gold) | [`docs/load_strategy/`](docs/load_strategy/) |
| **Silver validation & transformation set** | [`docs/silver_validation_and_transformation_set.md`](docs/silver_validation_and_transformation_set.md) |
| **dbt build guide + decision log** | [`docs/dbt/`](docs/dbt/) |
| **Authoritative DDL specs** | [`sql/`](sql/) (`bronze` · `silver` · `gold` · `audit`) |

---

## Development Workflow

```
main        production-ready (protected)
develop     integration branch for feature/*
feature/*   one branch per feature or table
hotfix/*    emergency fixes off main
```

CI runs on every push: **ruff** (lint), **mypy** (types), **pytest** (unit),
`docker compose config` validation, and a **`dbt build`** against an ephemeral `postgres:16` —
which compiles every model, enforces the contracts, and runs all **195 dbt data tests**, so a
broken model or failing test fails the PR before merge (not after).

---

## Roadmap

- [x] Bronze ingestion (Python EL) — 20 source tables, append-only
- [x] Silver layer — 20 contract-enforced incremental-merge models (`v0.1.0-silver`)
- [x] dbt data tests — 75 silver tests (`unique` / `not_null` / `accepted_values` / `relationships`) + source freshness SLA
- [x] Gold layer — 8 dims (6 SCD2) + 3 facts + 3 date views, 64 tests (`v0.2.0-gold`)
- [x] Governance — 20 ADRs, data dictionaries, mappings, load strategies, fix log
- [x] Wire the full pipeline end-to-end in Airflow with real batch IDs — incremental fact loads active
- [x] DRY the shared silver lineage/metadata block into a reusable macro (`silver_lineage_and_metadata`)
- [x] BI serving layer — star-native `gold.bi_*` views + Power BI DAX/build guide (ADR-017)
- [x] Least-privilege database roles — `pt_ingestion` / `pt_dbt` / `pt_bi_reader` (ADR-019)
- [x] Three external DW audits — every finding remediated or consciously accepted, **zero open** (`docs/audit/`, `docs/fix/`)
- [x] API source — FRED macro indicators (CPI, PPI) → real-terms revenue + margin-vs-cost (ADR-020)
- [ ] Tableau version of the dashboards (same serving views — for the managers to compare)

---

*PrintTimeUSA Data Warehouse — built with PostgreSQL, dbt Core, Apache Airflow, and pgAdmin,
running in Docker.*
