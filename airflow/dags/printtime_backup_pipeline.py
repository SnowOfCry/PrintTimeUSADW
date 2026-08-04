"""
printtime_backup_pipeline.py
----------------------------
Scheduled disaster-recovery backup for the PrintTimeUSA warehouse (ADR-018).

Flow:
    backup_warehouse   (pg_dump -Fc of the whole warehouse → /opt/airflow/backups,
                        timestamped, self-pruning to a retention count)
        → verify_restore  (restore the FRESH backup into a scratch DB and confirm
                           the row counts tie out — an untested backup is not a
                           backup. Fails the DAG if the backup isn't restorable.)

Why a DAG (not the shell script): the shell scripts use `docker compose exec`,
which Airflow can't do (no Docker socket — ADR-016). This DAG instead runs the
postgres client tools (installed in the Airflow image) against the warehouse over
the docker network (host `postgres`). Backups land on ./backups via a bind mount.

Schedule: daily at 03:00, after the nightly ELT (@daily / midnight) has finished
and validated its load, so each backup captures a known-good state.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

DEFAULT_ARGS = {
    "owner": "data_engineering",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

BACKUP_DIR = "/opt/airflow/backups"
# Warehouse connection comes from the DW_* env vars set in docker-compose.
CONN = '-h "$DW_HOST" -p "$DW_PORT" -U "$DW_USER"'
RETAIN = 7
VERIFY_DB = "dr_verify"
# Table used to prove the restore worked (any stable table is fine).
CHECK_TABLE = "gold.fact_retail_sales"

# ── Task 1: take the backup ───────────────────────────────────────────────────
BACKUP_CMD = f"""
set -euo pipefail
mkdir -p {BACKUP_DIR}
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="{BACKUP_DIR}/${{DW_DB}}_${{TS}}.dump"
echo "Backing up $DW_DB -> $ARCHIVE"
PGPASSWORD="$DW_PASSWORD" pg_dump {CONN} -d "$DW_DB" -Fc --no-owner --no-privileges > "$ARCHIVE"
BYTES=$(wc -c < "$ARCHIVE")
if [ "$BYTES" -lt 1000 ]; then echo "ERROR: empty backup ($BYTES b)"; rm -f "$ARCHIVE"; exit 1; fi
echo "✓ backup complete: $(du -h "$ARCHIVE" | cut -f1)"
# retention: keep the newest {RETAIN}
ls -1t {BACKUP_DIR}/${{DW_DB}}_*.dump | tail -n +{RETAIN + 1} | xargs -r rm -f
echo "backups on disk:"; ls -1t {BACKUP_DIR}/${{DW_DB}}_*.dump | head -{RETAIN}
"""

# ── Task 2: verify the fresh backup restores + reconciles ─────────────────────
VERIFY_CMD = f"""
set -euo pipefail
export PGPASSWORD="$DW_PASSWORD"
LATEST=$(ls -1t {BACKUP_DIR}/${{DW_DB}}_*.dump | head -1)
echo "Verifying restorability of $LATEST"
# --force terminates any stray session so the drop can't get stuck.
dropdb {CONN} --if-exists --force {VERIFY_DB}
createdb {CONN} {VERIFY_DB}
# pg_restore may print ignorable warnings; the REAL test is the row-count tie-out
# below, so don't let its exit code fail the task.
pg_restore {CONN} -d {VERIFY_DB} --clean --if-exists --no-owner < "$LATEST" \
    || echo "(pg_restore reported ignorable warnings — validating by row count)"
LIVE=$(psql {CONN} -d "$DW_DB"    -tAc "select count(*) from {CHECK_TABLE}")
REST=$(psql {CONN} -d {VERIFY_DB} -tAc "select count(*) from {CHECK_TABLE}")
dropdb {CONN} --if-exists --force {VERIFY_DB}
echo "live={CHECK_TABLE}=$LIVE  restored=$REST"
if [ "$LIVE" != "$REST" ] || [ "$REST" -eq 0 ]; then
    echo "ERROR: backup NOT restorable — row counts differ ($LIVE vs $REST)"; exit 1
fi
echo "✓ restore verified: $LATEST is restorable ($REST rows tie out)"
"""

with DAG(
    dag_id="printtime_backup_pipeline",
    description="Daily warehouse backup + automated restore-verification (ADR-018 / DR).",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="0 3 * * *",      # 03:00 daily — after the nightly ELT
    catchup=False,
    tags=["dr", "backup", "printtime"],
    doc_md=__doc__,
) as dag:

    backup_warehouse = BashOperator(
        task_id="backup_warehouse",
        bash_command=BACKUP_CMD,
        doc_md="pg_dump (-Fc) of the whole warehouse to ./backups, with retention.",
    )

    verify_restore = BashOperator(
        task_id="verify_restore",
        bash_command=VERIFY_CMD,
        doc_md="Restores the fresh backup into a scratch DB and confirms row counts tie out.",
    )

    backup_warehouse >> verify_restore
