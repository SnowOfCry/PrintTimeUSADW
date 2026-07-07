# ADR-002: Run the Warehouse Locally on Docker (PostgreSQL + Airflow + dbt) Instead of a Cloud Service

- **Status:** Accepted
- **Date:** 2026-04-04
- **Decision-makers:** Jaime Chavez Jr (CEO), Freddy Vazquez (Manager)
- **Proposed by:** Erick Palma (Data Engineer — presented the cost/benefit analysis of cloud vs local options)

## Context

PrintTimeUSA is building its first data warehouse. The platform choice determines recurring cost, operational responsibility, and where company data physically lives. Erick presented the options to Jaime and Freddy with costs, advantages, and disadvantages; because the company pays for the infrastructure, the platform decision was made by the business owners.

Facts that framed the analysis:

- **Scale is modest.** One source system, ~670k rows seeded, growth measured in thousands of rows per day — megabytes, not terabytes.
- **Cadence is daily batch.** No real-time or elastic-compute requirement.
- **One engineer** builds and operates everything.
- **Customer PII** (names, emails, phones of CA/AZ/TX customers) is involved; keeping it on company hardware simplifies the privacy posture.
- **Existing hardware** at the shop can host the stack at no incremental cost.

### Cost comparison presented

Typical published on-demand prices (US, rounded) for this workload — daily batch loads, single-digit GB of data, light BI querying during business hours:

| Option | Typical monthly cost | Notes |
|---|---|---|
| Snowflake (X-Small warehouse, ~2–4 h/day active) | ~$100–250 | $2–3/credit; storage negligible at our size |
| Amazon Redshift Serverless | ~$50–150 | 8-RPU minimum billed while active |
| Google BigQuery (on-demand) | ~$10–50 | Cheapest cloud DW at our scan volumes — rejected on PII locality and lock-in, not cost |
| Managed Postgres (RDS/Cloud SQL, ~2 vCPU/4 GB + storage/backups) | ~$60–90 | Database only |
| Managed Airflow (MWAA / Cloud Composer, smallest environment) | ~$350–450 | The dominant cost of the managed-stack route |
| dbt Cloud | $0–100 | Free single developer seat; Team tier $100/seat |
| **Managed-stack route total (RDS + MWAA + dbt Cloud)** | **≈ $420–600/mo (~$5,000–7,000/yr)** | |
| **Local Docker on existing hardware** | **≈ $0 incremental** | Electricity only; engineering effort identical in all options |

Engineering time (models, pipelines, documentation) is the same under every option, so the decision reduced to: recurring platform spend and PII locality versus operational responsibility.

## Decision

Run the entire warehouse **locally in Docker** on company hardware:

| Component | Choice |
|---|---|
| Warehouse database | PostgreSQL 16 (container) |
| Orchestration | Apache Airflow 2.9 (containers) |
| Transformations | dbt Core (container) |
| Admin / quality | pgAdmin, SonarQube (containers) |

Everything is defined in one `docker-compose.yml`: clone the repo, copy `.env`, `docker compose up`. The environment is reproducible on any machine, and because every component is an industry-standard open-source tool with cloud-managed equivalents (RDS/Cloud SQL, MWAA/Composer, dbt Cloud), a future cloud migration is a lift, not a rewrite.

## Alternatives considered

1. **Cloud data warehouse (Snowflake / BigQuery / Redshift).** Elastic compute and zero database operations — but a recurring monthly cost that is not justified at megabyte scale with daily batch loads, and it moves customer PII off-premises. The elasticity these platforms sell solves problems we do not have.
2. **Managed cloud equivalents of our stack (RDS/Cloud SQL + managed Airflow).** Architecturally closest to what we built, and the natural migration target later. Rejected for now: at ~$420–600/month (~$5,000–7,000/year, dominated by managed Airflow's ~$350–450 baseline), the spend buys operations relief we can currently cover ourselves, while the engineering work (models, pipelines, docs) is identical either way.
3. **Bare-metal local installs (no Docker).** Rejected: hand-configured servers drift and cannot be reproduced. Docker gives us versioned, disposable, identically-rebuildable environments — and made the dev/work-machine setup a 10-minute task.

## Consequences

**Positive**

- **~$0 incremental infrastructure cost** — existing hardware, open-source software, no licenses.
- **Data locality:** customer PII never leaves company equipment.
- **No vendor lock-in;** standard PostgreSQL/Airflow/dbt skills and artifacts transfer directly to any cloud later.
- **Reproducibility:** the full stack rebuilds identically from the repo on any machine.

**Negative / accepted costs**

- **We own operations** — backups, upgrades, monitoring, disaster recovery — with no managed SLA behind us. Mitigation: an operational runbook and backup schedule are required deliverables (tracked as a documentation gap).
- **Single-host ceiling:** no elasticity; capacity is the machine we run on. Accepted at current volumes.
- **Availability** is tied to office hardware and power — acceptable for internal, daily-cadence analytics.

**Revisit triggers** (proposed by engineering): reopen this decision and evaluate the cloud path (alternative 2) if any of the following happens:

- The data outgrows the machine it runs on — loads or backups struggle to finish.
- The numbers are no longer ready by the agreed morning hour, or dashboards become too slow for people to actually use.
- Enough people are using reports at the same time that one server can't keep up.
- Keeping the system running (backups, upgrades, fixing outages) starts taking more of the engineer's time than building new things.

## Related

- ADR-001 (medallion architecture — platform-agnostic by design)
- `docker-compose.yml`, `docker/postgres/init/` — the stack definition
- `docs/dw_readiness_review.md` — operational-documentation gap
