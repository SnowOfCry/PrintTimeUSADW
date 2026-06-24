# PrintTimeUSA — Local ELT Data Warehouse

A fully portable, Docker-based **ELT** data warehouse for PrintTimeUSA (retail company, Modesto CA).  
Clone the repo, copy `.env.example` to `.env`, and run `docker compose up -d` — no local installs required.

---

## Table of Contents

1. [Project Purpose](#1-project-purpose)
2. [ELT Architecture](#2-elt-architecture)
3. [Why ELT Instead of ETL](#3-why-elt-instead-of-etl)
4. [Folder Structure](#4-folder-structure)
5. [Docker Services](#5-docker-services)
6. [Getting Started](#6-getting-started)
7. [Stopping and Resetting](#7-stopping-and-resetting)
8. [Service URLs & Credentials](#8-service-urls--credentials)
9. [Airflow DAG](#9-airflow-dag)
10. [Python Ingestion Layer](#10-python-ingestion-layer)
11. [dbt Transformation Layer](#11-dbt-transformation-layer)
12. [SQL Scripts](#12-sql-scripts)
13. [Pipeline Logs & Watermarks](#13-pipeline-logs--watermarks)
14. [Git / GitHub Workflow](#14-git--github-workflow)
15. [Next Steps — Adding Real OLTP Extraction](#15-next-steps--adding-real-oltp-extraction)
16. [Next Steps — Adding Real dbt Models](#16-next-steps--adding-real-dbt-models)

---

## 1. Project Purpose

This project is the local development data warehouse for PrintTimeUSA.  
It extracts operational data from OLTP source systems, loads it into a raw bronze layer, and transforms it through clean silver and analytical gold layers using dbt — all orchestrated by Apache Airflow and running entirely inside Docker.

---

## 2. ELT Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AIRFLOW (Orchestration)                        │
│                                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐    ┌──────────┐ │
│  │ Extract  │───▶│  Load        │───▶│  Transform    │───▶│  Test    │ │
│  │ (Python) │    │  (Python)    │    │  (dbt)        │    │  (dbt)   │ │
│  └──────────┘    └──────────────┘    └───────────────┘    └──────────┘ │
│       │                 │                    │                          │
│  OLTP Source       bronze schema    silver → gold schemas               │
└─────────────────────────────────────────────────────────────────────────┘

PostgreSQL Schemas
──────────────────
bronze   Raw data as extracted (Python writes here)
silver   Cleaned, standardized, deduplicated (dbt writes here)
gold     Star-schema dimensions and facts (dbt writes here)
audit    Row counts, lineage, reconciliation records
control  Pipeline logs, watermarks, batch tracking
```

**Extract** — Python reads raw records from the OLTP source system, using watermarks for incremental loads.  
**Load** — Python writes raw records into `bronze` with no business transformations.  
**Transform** — dbt models clean bronze data into `silver`, then build dimensional models in `gold`.  
**Orchestrate** — Airflow DAGs schedule and sequence every step.  
**Monitor** — `control.elt_batch_log` tracks every pipeline run; `control.elt_watermark` tracks incremental progress.  
**Quality** — dbt tests validate data; SonarQube checks Python code quality.

---

## 3. Why ELT Instead of ETL

| Concern | ETL | ELT (this project) |
|---|---|---|
| Where transformations happen | In a separate tool before loading | Inside the warehouse using SQL (dbt) |
| Scalability | Transforms bound by ETL server | Transforms run on the warehouse engine |
| Auditability | Raw data often not kept | Raw data always available in bronze |
| Developer experience | Two languages tightly coupled | Python owns extraction only; SQL owns all business logic |
| Re-processing | Must re-extract to change logic | Re-run dbt against existing bronze |

---

## 4. Folder Structure

```
PrintTimeUSADW/
│
├── docker/                         Docker build contexts
│   ├── postgres/
│   │   ├── init/
│   │   │   ├── 001_create_schemas.sql
│   │   │   └── 002_create_control_tables.sql
│   │   └── Dockerfile
│   ├── airflow/
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   ├── dbt/
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── sonarqube/
│       └── sonar-project.properties
│
├── airflow/
│   ├── dags/
│   │   └── printtime_elt_pipeline.py ← ELT pipeline Airflow DAG
│   ├── logs/                         ← Git-ignored; written at runtime
│   ├── plugins/
│   └── config/
│
├── ingestion/                       Python EL layer (Extract + Load only)
│   ├── extract/
│   │   └── oltp_extractor.py
│   ├── load/
│   │   └── bronze_loader.py
│   ├── utils/
│   │   ├── database.py
│   │   ├── logger.py
│   │   ├── config_loader.py
│   │   └── watermark.py
│   ├── config/
│   │   └── ingestion_config.yml
│   └── main.py
│
├── dbt/
│   └── printtime_dw/
│       ├── dbt_project.yml
│       ├── profiles.yml
│       ├── models/
│       │   ├── bronze/              dbt source declarations
│       │   ├── silver/              cleaning + standardization models
│       │   └── gold/                dimensional models
│       ├── macros/
│       ├── seeds/
│       ├── snapshots/
│       └── tests/
│
├── sql/                             Plain SQL scripts (not dbt)
│   ├── bronze/
│   ├── silver/
│   ├── gold/
│   ├── audit/
│   └── control/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   └── data_quality/
│
├── docs/
│   ├── architecture/
│   ├── naming_conventions/
│   ├── source_to_dw_mapping/
│   └── data_dictionary/
│
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   ├── reset.sh
│   └── healthcheck.sh
│
├── .github/workflows/ci.yml
├── .env.example
├── .gitignore
├── docker-compose.yml
├── requirements-dev.txt
└── README.md
```

---

## 5. Docker Services

| Service | Image | Port | Purpose |
|---|---|---|---|
| `postgres` | postgres:16 (custom) | 5432 | Data warehouse database |
| `pgadmin` | dpage/pgadmin4:8.9 | 5050 | PostgreSQL GUI |
| `airflow-init` | custom Airflow 2.9.3 | — | DB migration + admin user creation (runs once) |
| `airflow-webserver` | custom Airflow 2.9.3 | 8080 | Airflow UI |
| `airflow-scheduler` | custom Airflow 2.9.3 | — | DAG scheduling |
| `dbt` | custom Python 3.11 | — | dbt Core + dbt-postgres (run ad-hoc) |
| `sonarqube` | sonarqube:10.6-community | 9000 | Code quality analysis |

All services share a single Docker bridge network: `elt_network`.

---

## 6. Getting Started

### Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
- Git installed.

### Step 1 — Clone the repository
```bash
git clone https://github.com/<your-org>/PrintTimeUSADW.git
cd PrintTimeUSADW
```

### Step 2 — Create your environment file
```bash
cp .env.example .env
```
Open `.env` and fill in your passwords. **Never commit `.env` to Git.**

Generate `AIRFLOW_FERNET_KEY`:
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### Step 3 — Start the stack
```bash
bash scripts/start.sh
```
Or manually:
```bash
docker compose build
docker compose up -d
```

### Step 4 — Verify
```bash
bash scripts/healthcheck.sh
```

---

## 7. Stopping and Resetting

**Stop (preserve data):**
```bash
bash scripts/stop.sh
```

**Full reset — DELETE all data:**
```bash
bash scripts/reset.sh
```

---

## 8. Service URLs & Credentials

| Service | URL | Default Credential (from `.env.example`) |
|---|---|---|
| pgAdmin | http://localhost:5050 | `admin@printtime.local` / `changeme_pgadmin` |
| Airflow | http://localhost:8080 | `admin` / `changeme_admin` |
| SonarQube | http://localhost:9000 | `admin` / `admin` (first login) |
| PostgreSQL | `localhost:5432` | `warehouse_user` / `changeme_warehouse` |

> Change all passwords before using this project with any real data.

### Connecting pgAdmin to PostgreSQL
1. Open http://localhost:5050 and log in.
2. Right-click **Servers → Register → Server**.
3. **General** tab → Name: `PrintTimeUSA DW`
4. **Connection** tab → Host: `postgres`, Port: `5432`, DB: `printtime_dw`, Username/Password from `.env`

---

## 9. Airflow DAG

File: [`airflow/dags/printtime_elt_pipeline.py`](airflow/dags/printtime_elt_pipeline.py)

```
start_pipeline
    → ingest_oltp_to_bronze  PythonOperator — extract every configured table → bronze
    → run_dbt_silver         BashOperator   — dbt run --select silver
    → run_dbt_gold           BashOperator   — dbt run --select gold
    → run_dbt_tests          BashOperator   — dbt test
    → update_control_logs    PythonOperator — updates batch log
end_pipeline
```

Trigger manually: Airflow UI → `printtime_elt_pipeline` → **▶ Trigger DAG**

---

## 10. Python Ingestion Layer

Location: [`ingestion/`](ingestion/)

Python is responsible **only** for:
- Connecting to the OLTP source
- Extracting raw data using watermarks for incremental loads
- Loading raw records into `bronze` with zero business transformations
- Writing to `control.elt_batch_log` and `control.elt_watermark`

Python is **NOT** responsible for cleaning data, building dimensions, or any dbt logic.

| File | Purpose |
|---|---|
| `ingestion/extract/oltp_extractor.py` | Reads rows from OLTP source |
| `ingestion/load/bronze_loader.py` | Writes raw DataFrames to `bronze` |
| `ingestion/utils/database.py` | Connection helpers |
| `ingestion/utils/watermark.py` | Read/update watermarks |
| `ingestion/utils/logger.py` | Structured logging |
| `ingestion/utils/config_loader.py` | YAML + env var config |
| `ingestion/config/ingestion_config.yml` | Source table list |

---

## 11. dbt Transformation Layer

Location: [`dbt/printtime_dw/`](dbt/printtime_dw/)

| Layer | Schema | What dbt does |
|---|---|---|
| Bronze | `bronze` | Source declarations + freshness checks |
| Silver | `silver` | Cleans, casts, deduplicates, standardizes |
| Gold | `gold` | Star-schema dimensions (dim_*) and facts (fct_*) |

```bash
# Verify connection
docker compose run --rm dbt dbt debug

# Run silver models
docker compose run --rm dbt dbt run --select silver

# Run gold models
docker compose run --rm dbt dbt run --select gold

# Run all dbt tests
docker compose run --rm dbt dbt test

# Build silver + gold + tests in one command
docker compose run --rm dbt dbt build --select silver gold
```

---

## 12. SQL Scripts

Location: [`sql/`](sql/)

| Folder | Purpose |
|---|---|
| `sql/bronze/` | Ad-hoc raw data queries, manual bronze table DDL |
| `sql/silver/` | Prototype silver queries before converting to dbt |
| `sql/gold/` | Prototype gold queries |
| `sql/audit/` | Reconciliation counts, lineage inserts |
| `sql/control/` | Manual control-table operations |

---

## 13. Pipeline Logs & Watermarks

```sql
-- Check recent pipeline runs
SELECT pipeline_name, status, records_loaded, started_at, ended_at, error_message
FROM   control.elt_batch_log
ORDER  BY started_at DESC
LIMIT  20;

-- Check watermarks
SELECT pipeline_name, source_table, watermark_column, last_watermark_value, updated_at
FROM   control.elt_watermark
WHERE  is_active = TRUE;
```

---

## 14. Git / GitHub Workflow

```
main        ← production-ready; protected branch
develop     ← integration; merge feature/* here
feature/*   ← one branch per feature or OLTP table
hotfix/*    ← emergency fixes off main
```

CI runs on every push: lint (ruff), type check (mypy), unit tests (pytest), docker compose validate.

---

## 15. Next Steps — Adding Real OLTP Extraction

1. Add OLTP credentials (`OLTP_HOST`, `OLTP_DB`, `OLTP_USER`, `OLTP_PASSWORD`) to `.env`
2. Implement `get_oltp_connection()` in [`ingestion/utils/database.py`](ingestion/utils/database.py)
3. Add source tables to [`ingestion/config/ingestion_config.yml`](ingestion/config/ingestion_config.yml)
4. Implement `extract_table()` in [`ingestion/extract/oltp_extractor.py`](ingestion/extract/oltp_extractor.py) using `pd.read_sql()`
5. Implement `load_dataframe_to_bronze()` in [`ingestion/load/bronze_loader.py`](ingestion/load/bronze_loader.py) using `df.to_sql()`
6. Uncomment real SQL in [`ingestion/utils/watermark.py`](ingestion/utils/watermark.py)
7. Wire the Airflow DAG — the real extractor/loader calls live in [`airflow/dags/printtime_elt_pipeline.py`](airflow/dags/printtime_elt_pipeline.py)
8. Add `CREATE TABLE IF NOT EXISTS bronze.raw_<table>` scripts to `sql/bronze/` and run them once

---

## 16. Next Steps — Adding Real dbt Models

**Silver:** create `.sql` files in `dbt/printtime_dw/models/silver/` that read from `{{ source('bronze', 'raw_<table>') }}`, apply cleaning, and add entries to `_silver_models.yml`.

**Gold:** create `.sql` files in `dbt/printtime_dw/models/gold/` that read from `{{ ref('stg_<table>') }}`, build surrogate keys, dimensions, and facts, and add entries to `_gold_models.yml`.

**Sources:** update `_bronze_sources.yml` to declare every real bronze table.

**Tests:** add `unique`, `not_null`, and `relationships` tests to every model's `.yml` entry.

---

*PrintTimeUSA ELT Data Warehouse — built with Apache Airflow, dbt Core, PostgreSQL, pgAdmin, and SonarQube running in Docker.*
