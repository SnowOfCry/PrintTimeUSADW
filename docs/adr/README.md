# Architecture Decision Records (ADRs)

PrintTimeUSA Data Warehouse. Each ADR captures one significant decision — its context, the alternatives weighed, the choice, and the consequences accepted — so the *why* behind the design is durable and reviewable.

**Format:** each record follows Context → Decision → Alternatives considered → Consequences, with a Status/Date/Decision-makers header. Superseded decisions are kept (never deleted) and marked as such.

**Statuses:** `Accepted` · `Proposed` · `Superseded` · `Deprecated`

## Index

| # | Title | Status | Decision-makers |
|---|---|---|---|
| [001](001-adopt-medallion-architecture.md) | Adopt a medallion architecture (bronze → silver → gold), star-schema gold | Accepted | Erick Palma |
| [002](002-local-docker-stack-over-cloud.md) | Run locally on Docker (PostgreSQL + Airflow + dbt) instead of a cloud service | Accepted | Jaime Chavez Jr, Freddy Vazquez |
| [003](003-elt-over-etl.md) | ELT over ETL — Python extracts/loads only; transformations in the warehouse | Accepted | Erick Palma |
| [004](004-bronze-append-only.md) | Bronze is append-only (immutable raw history) | Accepted | Erick Palma |
| [005](005-silver-transformation-standards.md) | Silver transformation standards (cast, normalize, vocabularies, derived flags) | Accepted | Erick Palma |
| [006](006-silver-incremental-merge.md) | Silver load strategy — incremental merge to one current row per business key | Accepted | Erick Palma |
| [007](007-gold-mixed-load-strategy.md) | Gold load strategy — SCD2 dimensions plus per-grain fact loads | Accepted | Erick Palma |
| [008](008-consolidate-etl-control-into-audit-schema.md) | Consolidate ETL batch control into the audit schema | Accepted | Erick Palma |
| [009](009-facts-carry-no-source-business-keys.md) | Facts carry no source business keys (reload at parent grain) | Accepted | Erick Palma |
| [010](010-role-playing-date-views.md) | Role-playing date views over a single `dim_date` | Accepted | Erick Palma |
| [011](011-unknown-members-and-unenforced-fks.md) | `-1` "Not Provided" members and unenforced foreign keys on facts | Accepted | Erick Palma |
| [012](012-data-quality-strategy.md) | Data quality & validation strategy (severity tiers) | Accepted | Erick Palma, Freddy Vazquez |
| [013](013-data-governance-and-pii.md) | Data governance — PII classification, access, retention, deletion | Accepted | Jaime Chavez Jr, Freddy Vazquez |
| [014](014-customer-county-not-provided.md) | Accept `dim_customer.customer_county` as 'Not Provided' (no source) | Accepted | Erick Palma |
| [015](015-gold-scd2-dbt-implementation.md) | Gold SCD2 dimensions — custom incremental dbt model (append + post-hooks) over dbt snapshots | Accepted | Erick Palma |
| [016](016-run-dbt-inside-the-airflow-image.md) | Run dbt inside the Airflow image (BashOperator) rather than DockerOperator | Accepted | Erick Palma |
| [017](017-bi-tool-power-bi-then-tableau.md) | Power BI as the BI tool on a tool-agnostic serving layer; Tableau version to follow for the managers to decide | Accepted | Erick Palma |
| [018](018-disaster-recovery-and-backup.md) | Disaster recovery — tested logical backup/restore, backed by medallion reproducibility (closes audit HIGH-5) | Accepted | Erick Palma |
| [019](019-least-privilege-database-roles.md) | Least-privilege database roles (RBAC) — split the superuser into pt_ingestion / pt_dbt / pt_bi_reader (implements ADR-013 §3, closes audit HIGH-6) | Accepted | Erick Palma |
| [020](020-external-fred-macro-source.md) | External macroeconomic source (FRED API) — first API source; CPI/PPI for real-terms revenue + input-cost analysis | Accepted | Erick Palma |

## Reading order

- **Foundations:** 001 (architecture) → 002 (stack) → 003 (ELT)
- **Per layer:** 004 (bronze) → 005–006 (silver) → 007 (gold) → 008 (audit/control)
- **Gold modeling details:** 009 (lean facts) · 010 (date views) · 011 (Not Provided members) · 015 (SCD2 dbt implementation)
- **Orchestration:** 016 (how Airflow runs dbt)
- **BI / serving:** 017 (Power BI on a gold serving layer; Tableau to follow)
- **Operations / DR:** 018 (backup, restore, and reproducibility) · 019 (least-privilege roles / RBAC)
- **Cross-cutting:** 012 (data quality) · 013 (governance/PII) · 014 (customer_county gap)

## Adding a new ADR

1. Copy the structure of an existing record; number it sequentially (`NNN-short-slug.md`).
2. Fill Context → Decision → Alternatives → Consequences; set Status/Date/Decision-makers.
3. Add a row to the index above.
4. If it replaces an earlier decision, mark the old one `Superseded by ADR-NNN` (keep it).
