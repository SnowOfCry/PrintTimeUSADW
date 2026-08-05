# ADR-019: Least-Privilege Database Roles (RBAC)

- **Status:** Accepted
- **Date:** 2026-08-04
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Implements:** ADR-013 §3 (Access model)
- **Closes:** external audit finding **HIGH-6** (one all-privilege database user)

## Context

ADR-013 §3 defined a least-privilege access model — engineering full, BI read-only
on gold, service accounts least-privilege — but it was **never implemented**. Every
service (Python ingestion, dbt, Airflow's DW connection, pgAdmin, SonarQube)
authenticated as the single superuser `warehouse_user`. The external audit flagged
this as **HIGH-6** and made the sharp point that ADR-013's headline PII-minimization
claim — *"BI users never see raw contact PII — minimization is structural"* — was
false in practice: with one superuser, **any connected client could read
`silver.customer.silver_email` / `silver_phone_number`.** The minimization was
documented but not enforced. Blast radius was the whole warehouse: compromise any one
service and you have every layer, including PII.

## Decision

**Split the single superuser into three least-privilege LOGIN roles**, defined in
`sql/security/001_create_roles.sql` (idempotent) and applied with
`scripts/apply_roles.sh` (passwords injected as psql variables from `PT_*` env vars —
never written into the SQL).

| Role | Privileges | Used by |
|---|---|---|
| **`pt_ingestion`** | `USAGE`+`SELECT`+`INSERT` on **bronze**; `SELECT`+`INSERT`+`UPDATE` on **audit** (watermark/batch state); sequence `USAGE`. No silver/gold. | Python ingestion + the DAG's batch-control/watermark tasks (`DW_*`) |
| **`pt_dbt`** | `SELECT` on **bronze**+**audit** (gold facts read `audit.etl_batch_control`); **owns silver + gold** (full DDL to create/drop/replace models). Cannot write bronze. Writes **`audit.audit_log` only** via `INSERT` — the fact-reload change trail (MED-4) — never `etl_batch_control`. | dbt (`DBT_*`) |
| **`pt_bi_reader`** | `USAGE`+`SELECT` on **gold only**. No `USAGE` on bronze/silver/audit. | Power BI / analysts / managers |
| `warehouse_user` | Superuser (unchanged) — admin, pgAdmin, Airflow-metadata connection, break-glass, and the **backup DAG** (which needs dump-all + createdb/dropdb). | Admin / DR |

`ALTER DEFAULT PRIVILEGES` is set so future objects keep the grants automatically:
new bronze/audit tables stay writable by `pt_ingestion`/readable by `pt_dbt`, and new
gold models created by `pt_dbt` stay readable by `pt_bi_reader`.

### Why the backup DAG stays on the admin role
Backup/restore is intrinsically privileged: `pg_dump` must read **every** schema and
`verify_restore` must `createdb`/`dropdb` a scratch database — privileges the ELT
roles deliberately lack. Rather than weaken `pt_ingestion`, the backup DAG
(ADR-018) uses a dedicated admin connection (`BACKUP_DB_*` → `warehouse_user`),
keeping least privilege intact for the pipeline while DR keeps the power it needs.

### Verification (proven, not assumed)
Applied to the live warehouse and each boundary tested:

- `pt_bi_reader` reads `gold.fact_retail_sales` (66,010 rows) but is **denied** on
  `silver` (PII) and `bronze` — *"permission denied for schema silver"*. The
  minimization is now structural, as ADR-013 §2 claimed.
- `pt_ingestion` reads/inserts bronze and updates the audit watermark, but is
  **denied** on silver.
- `pt_dbt` reads bronze, **owns** gold (create/drop verified), and is **denied**
  writing bronze. A real `dbt build` (gold view + reconciliation test) ran green
  authenticating as `pt_dbt`.
- The rewired backup DAG ran green under `BACKUP_DB_*` (admin), confirming the split.

## Alternatives considered

1. **NOLOGIN group roles + separate login users granted membership.** The textbook
   two-tier pattern. Deferred: at one engineer plus a few BI users, three direct
   LOGIN roles are simpler and the grants are identical. Revisit if the number of
   human users grows.
2. **Column-level masking of PII in silver/gold.** Heavier; rejected in ADR-013 §2
   (Alternative 2) for an internal on-prem DW. Schema-level `USAGE` denial already
   makes BI's PII exposure structurally impossible.
3. **Separate databases per service (Airflow metadata, SonarQube).** The audit's
   phase-2 recommendation. Out of scope here (phase 1 = the role split). Since
   addressed in part by **removing SonarQube** (2026-08-04) — it was unused (its CI
   scan was never enabled) and, as a third-party app holding warehouse-owner creds,
   was pure liability; the DW's real quality gate is its 160+ dbt tests. Only the
   shared Airflow-metadata DB co-tenancy remains open.

## Consequences

**Positive**
- ADR-013's PII-minimization is now **enforced**, not just documented — BI cannot
  reach `silver`/`bronze`. Closes HIGH-6.
- Blast radius is contained: a compromised BI connection reads gold only; a
  compromised ingestion connection cannot touch silver/gold or read PII.
- Reproducible and idempotent: `apply_roles.sh` re-runs safely as models evolve.

**Negative / accepted gaps** *(honest — the next steps)*
- **Database separation not fully done** (phase 2): Airflow metadata still shares
  the warehouse DB. (SonarQube — the other co-tenant that held owner creds — was
  removed 2026-08-04, closing that part of the gap.)
- Passwords are dev-grade (`changeme_*`) in the local `.env`; production should use a
  secrets manager. On-prem, not-internet-exposed posture (ADR-002) bounds the risk.
- On a **from-scratch rebuild**, roles must be applied *after* the layer DDL exists
  (the script transfers ownership of / grants on existing objects): create schemas +
  bronze/silver/gold/audit DDL as `warehouse_user`, then run `apply_roles.sh`.

## Related
- ADR-013 (governance/PII — the access model this implements), ADR-002 (on-prem
  posture — why risk is bounded), ADR-018 (backup DAG — why it keeps admin creds)
- `sql/security/001_create_roles.sql`, `scripts/apply_roles.sh`
- `docs/audit/002-external-dw-audit.md` — finding HIGH-6
