# ADR-018: Disaster Recovery — Backup, Restore, and Reproducibility

- **Status:** Accepted
- **Date:** 2026-08-03
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Closes:** external audit finding **HIGH-5** (no disaster recovery)

## Context

The platform had **no disaster-recovery capability** — no backups, no restore procedure,
no RPO/RTO, nothing tested. The external audit flagged this as the single gate blocking a
PRE-PRODUCTION rating (DR scored 0/5). A warehouse without a proven recovery path is one disk
failure or bad migration away from unrecoverable data loss.

Two facts shape the right strategy here:

1. **The warehouse is largely reproducible.** Bronze is append-only and immutable (ADR-004),
   and silver/gold are deterministic dbt transformations. Given bronze + the audit/watermark
   state + the code, silver and gold can be rebuilt with `dbt build --full-refresh`. So the
   *irreplaceable* data is bronze and the batch-control state; everything downstream is derived.
2. **The OLTP source is the system of record.** The warehouse ingests from it. If bronze were
   lost, the pipeline can re-ingest from the source (subject to the source's own retention).

## Decision

**Adopt a logical-backup + tested-restore capability, backed by the medallion layer's
reproducibility as the fallback recovery path.**

1. **Backups** (`scripts/backup_warehouse.sh`): a compressed `pg_dump` (custom format, `-Fc`)
   of the entire warehouse database — bronze, silver, gold, and the `audit` schema (which holds
   the watermark/batch state) — written to `./backups` with a timestamped name and a retention
   count (default 7). Custom format supports selective and parallel restore.
2. **Restore** (`scripts/restore_warehouse.sh`): `pg_restore --clean` from any archive, with a
   confirmation prompt (destructive against the live DB) and the option to restore into a
   **scratch database** to validate a backup without touching production.
3. **Reproducibility fallback:** if a backup is unusable, recover bronze (from backup or by
   re-ingesting from the OLTP source) and rebuild silver/gold with `dbt build --full-refresh`.
   This is why bronze immutability (ADR-004) is a DR feature, not just a lineage one.
4. **Test the restore, always.** DR is only real if the restore is proven. The restore was
   validated by restoring a fresh backup into a scratch DB and confirming row counts match the
   source exactly (`fact_retail_sales`, `silver.invoice_line`, `dim_customer` all tied out).

### RPO / RTO

| Objective | Target | Basis |
|---|---|---|
| **RPO** (max data loss) | **≤ 24h** | Daily backups; and because the OLTP source retains the data and the pipeline re-ingests, a lost day is **recoverable by re-running the pipeline**, not just by restoring. |
| **RTO** (time to recover) | **~minutes** | Measured: restoring the ~28 MB warehouse into a scratch DB took **~61 seconds**. Full rebuild from bronze via dbt is the fallback (single-digit minutes at current volume). |

### Scheduling & automated verification

Backups are **automated by a dedicated Airflow DAG** — `airflow/dags/printtime_backup_pipeline.py`,
scheduled daily at 03:00 (after the nightly ELT has validated its load, so each backup captures a
known-good state). Because Airflow can't `docker exec` into the postgres container (no Docker
socket — ADR-016), the DAG runs the postgres client tools (installed in the Airflow image, pinned
to `postgresql-client-16` to match the server) against the warehouse over the docker network;
archives land on the host via a `./backups` bind mount.

The DAG has **two tasks**: `backup_warehouse` (pg_dump + retention) → `verify_restore`. The second
is the important one: it **restores the fresh backup into a scratch database and confirms the row
counts tie out**, so an unrestorable backup *fails the DAG*. An untested backup is not a backup —
here every backup is tested automatically. (The shell scripts remain for manual/ad-hoc use.)

## Alternatives considered

1. **Physical backup + WAL archiving (point-in-time recovery).** More powerful — recover to any
   second, near-zero RPO. Rejected for now: significant operational overhead (WAL shipping,
   base backups, archive management) that a daily-batch warehouse at megabyte scale doesn't need.
   The reproducibility of the medallion layers already bounds real data loss. Revisit if the
   warehouse becomes latency-critical or much larger.
2. **Rely on reproducibility alone (no backups).** Bronze + dbt *can* rebuild everything — but
   only if bronze itself survives, and a full rebuild is slower than a restore. Backups give a
   fast path and protect bronze/audit state. Reproducibility is the *fallback*, not the plan.
3. **Managed cloud backups (RDS automated snapshots).** The natural answer once on AWS (ADR-002),
   and where this should go for production — automated, offsite, point-in-time. Out of scope for
   the local stack; the logical backups here are the on-prem equivalent and migrate cleanly.

## Consequences

**Positive**
- A real, **tested** recovery path where there was none — closes the audit's PRE-PRODUCTION gate.
- Fast RTO (~1 min restore) plus a reproducibility fallback if a backup is ever bad.
- Backups include the `audit` watermark state, so a restore resumes incremental loads correctly.
- Portable: `pg_dump` archives restore to any Postgres, including a future RDS instance.

**Negative / accepted gaps** *(honest — these are the next steps)*
- **Not offsite.** Backups sit on the same host (`./backups`, git-ignored) — this violates 3-2-1.
  Next step: sync to object storage (S3) so a host loss doesn't take the backups with it.
- **No point-in-time recovery** — RPO is a day, not a second. Acceptable for daily batch.
- The **OLTP source's** own backup is out of scope (it's the operational system of record).

## Update (2026-08-14) — restore drill scheduled and proven (closes AUDIT-003-M5)

Audit 003 kept M5 open because the restore was "scripted but not proven on a schedule." It now is:
the `printtime_backup_pipeline` DAG runs **daily at 10:00 America/Los_Angeles** (after the 08:00
ELT) and its `verify_restore` task **restores the fresh dump into a throwaway `dr_verify` database
and reconciles row counts** against live — failing loudly if they differ or the restore is empty.
Proven on a live run: `live=gold.fact_retail_sales=67050  restored=67050 → ✓ restore verified`.
Backups retain the newest 7 dumps (~32 MB each). Remaining (backlog, not blocking): an **offsite
copy** of the dumps — on this local box they share the host disk.

## Related
- ADR-004 (bronze append-only — the reproducibility that underpins the fallback)
- ADR-002 (local Docker stack — RDS automated snapshots are the cloud target)
- ADR-008 (audit/batch-control state, included in the backup so watermarks survive a restore)
- `scripts/backup_warehouse.sh`, `scripts/restore_warehouse.sh`
- `docs/audit/` — external audit finding HIGH-5
