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

## Reading order

- **Foundations:** 001 (architecture) → 002 (stack) → 003 (ELT)
- **Per layer:** 004 (bronze) → 005–006 (silver) → 007 (gold) → 008 (audit/control)
- **Gold modeling details:** 009 (lean facts) · 010 (date views) · 011 (Not Provided members) · 015 (SCD2 dbt implementation)
- **Cross-cutting:** 012 (data quality) · 013 (governance/PII) · 014 (customer_county gap)

## Adding a new ADR

1. Copy the structure of an existing record; number it sequentially (`NNN-short-slug.md`).
2. Fill Context → Decision → Alternatives → Consequences; set Status/Date/Decision-makers.
3. Add a row to the index above.
4. If it replaces an earlier decision, mark the old one `Superseded by ADR-NNN` (keep it).
