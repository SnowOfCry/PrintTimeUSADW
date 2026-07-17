# PrintTimeUSA Data Warehouse

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
- **Design decided in the open** — 14 Architecture Decision Records ([`docs/adr/`](docs/adr/))
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
| Code quality | SonarQube, ruff, mypy, pytest (CI on every push) |
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
| **Silver** (20 models) | ✅ **Complete** — contract-enforced incremental merge, `dbt build --select silver` passes 20/20 |
| **Gold** (Kimball star schema) | 🚧 Designed (DDL, mappings, dictionary); dbt models in progress |
| **Audit** (batch control + lineage) | ✅ In place |
| **Orchestration** (Airflow DAG) | 🚧 Wired end-to-end; runs against the current layers |
| **Governance** (14 ADRs, dictionaries, mappings) | ✅ Complete |

The silver layer is the current centerpiece: every one of the 20 models applies the same
pattern — deduplicate append-only bronze to one current row per business key, cast to the DDL
types, normalize per ADR-005, compute a change-detection hash, and merge incrementally with a
build-time contract enforcing types, `NOT NULL`s, and the primary key.

---

## Repository Structure

```
PrintTimeUSADW/
├── docker/                          Docker build contexts (postgres, airflow, dbt, sonarqube)
├── airflow/
│   └── dags/printtime_elt_pipeline.py   ELT pipeline DAG
├── ingestion/                       Python Extract + Load (no business logic)
│   ├── extract/  load/  utils/  config/  main.py
├── dbt/printtime_dw/                dbt project
│   ├── dbt_project.yml  profiles.yml
│   ├── macros/generate_schema_name.sql
│   └── models/
│       ├── bronze/_bronze_sources.yml      source declarations (oltp_*, ref_*)
│       ├── silver/                         20 models + _silver_models.yml (contracts)
│       └── gold/                           dimensional models (in progress)
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
| `sonarqube` | sonarqube community | 9000 | Code quality analysis |

All services share one Docker bridge network, `elt_network`. Inside the network, containers
reach Postgres at `postgres:5432`; from your host, use `localhost:5433`.

---

## Service URLs & Credentials

| Service | URL | Default credential (from `.env.example`) |
|---|---|---|
| pgAdmin | http://localhost:5050 | `admin@printtime.local` / `changeme_pgadmin` |
| Airflow | http://localhost:8080 | `admin` / `changeme_admin` |
| SonarQube | http://localhost:9000 | `admin` / `admin` (first login) |
| PostgreSQL | `localhost:5433` | `warehouse_user` / `changeme_warehouse` |

> These are development defaults. **Change every password before using real data.**

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
  → ingest_oltp_to_bronze   PythonOperator — extract each configured table → bronze
  → run_dbt_silver          BashOperator   — dbt run --select silver
  → run_dbt_gold            BashOperator   — dbt run --select gold
  → run_dbt_tests           BashOperator   — dbt test
  → update_control_logs     PythonOperator — finalize batch records in audit
end_pipeline
```

Trigger manually from the Airflow UI (`printtime_elt_pipeline` → **Trigger DAG**), or on schedule.

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
| **Architecture Decision Records** (001–014) | [`docs/adr/`](docs/adr/) — start at [the index](docs/adr/README.md) |
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

CI runs on every push: **ruff** (lint), **mypy** (types), **pytest** (unit), and
`docker compose config` validation. Data quality is enforced by **dbt tests** and the model
contracts.

---

## Roadmap

- [x] Bronze ingestion (Python EL) — 20 source tables, append-only
- [x] Silver layer — 20 contract-enforced incremental-merge models
- [x] Governance — 14 ADRs, data dictionaries, mappings, load strategies
- [ ] dbt data tests (`unique` / `not_null` / `relationships`) alongside contracts
- [ ] DRY the shared lineage/metadata block into a reusable macro
- [ ] Gold layer — SCD2 dimensions + per-grain fact loads ([ADR-007](docs/adr/007-gold-mixed-load-strategy.md))
- [ ] Wire the full pipeline end-to-end in Airflow with real batch IDs

---

*PrintTimeUSA Data Warehouse — built with PostgreSQL, dbt Core, Apache Airflow, pgAdmin, and
SonarQube, running in Docker.*
