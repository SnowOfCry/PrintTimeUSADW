"""
printtime_elt_pipeline.py
-------------------------
PrintTimeUSA Data Warehouse — end-to-end ELT pipeline.

Flow:
    start_pipeline
        → ingest_oltp_to_bronze     (Python: extract OLTP → bronze; logs its own batches)
        → start_silver_batch        (audit.etl_batch_control: 'running' row → batch_key)
        → run_dbt_silver            (dbt run --select silver --vars silver_batch_id=<key>)
        → complete_silver_batch     (marks the batch 'succeeded' + rows from run_results)
        → start_gold_batches        (one 'running' row per gold target)
        → run_dbt_gold              (dbt run --select gold)
        → run_dbt_tests             (dbt test — GATES the watermark; fails the DAG on breakage)
        → complete_gold_batches     (marks them 'succeeded' → facts' watermark advances)
    end_pipeline
    fail_open_batches               (only when something failed: closes 'running' rows)

Tests run BEFORE complete_gold_batches (HIGH-7): validation gates the watermark
commit rather than trailing it, so a failing test holds the gold batches
'running' and the facts' watermark does not advance past unvalidated data.

Why the batch tasks matter (ADR-008 + gold load strategy):
- Silver rows are stamped with silver_batch_id = the batch_key opened here, so
  every row traces to a run in audit.etl_batch_control (no more -1 ad-hoc marker).
- The gold facts find "what changed" by comparing silver_updated_at_timestamp
  against the LAST SUCCEEDED gold batch for their target table. Completing the
  gold batches here is what switches the facts from safe full reloads to
  genuinely incremental loads.
- fact_customer_behavior_snapshot self-gates: it appends only when its month-end
  snapshot_date_key doesn't exist yet, so the daily schedule yields exactly one
  snapshot per month with no DAG-level date logic.

dbt execution (orchestration decision, Option A): dbt-core/dbt-postgres are
installed in the Airflow image at the same pinned versions as docker/dbt, the
project is mounted at /dbt/printtime_dw, and profiles.yml reads the DBT_* env
vars set in docker-compose. The dedicated dbt service remains for ad-hoc use.
"""

from __future__ import annotations

import json
import os
import urllib.request
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from airflow.utils.trigger_rule import TriggerRule

PIPELINE_NAME = "printtime_elt_pipeline"


# ---------------------------------------------------------------------------
# Failure alerting (AUDIT-003-M1)
# ---------------------------------------------------------------------------
def alert_on_failure(context: dict) -> None:
    """Fire on ANY task failure so a broken run is never silent.

    Always emits a structured ALERT log line (visible in the scheduler logs and
    testable without any external channel), then pushes the same message to a
    channel if one is configured: Slack (`ALERT_SLACK_WEBHOOK`) or email
    (`ALERT_EMAIL`, via Airflow's SMTP). Best-effort by design — a broken alert
    channel must never raise and mask or worsen the original task failure, so
    every side effect is wrapped and swallowed.
    """
    ti = context.get("task_instance")
    dag_id = getattr(ti, "dag_id", PIPELINE_NAME)
    task_id = getattr(ti, "task_id", "unknown")
    run_id = context.get("run_id", "unknown")
    exc = context.get("exception")
    log_url = getattr(ti, "log_url", "")
    msg = (f"[ALERT] {dag_id} FAILED — task={task_id} run={run_id} "
           f"error={exc} log={log_url}")

    # 1) Always log it — the one path that works with zero configuration.
    try:
        from ingestion.utils.logger import get_logger
        get_logger(__name__).error(msg)
    except Exception:
        print(msg)

    # 2) Slack webhook, if configured (stdlib only — no extra dependency).
    webhook = os.environ.get("ALERT_SLACK_WEBHOOK")
    if webhook:
        try:
            req = urllib.request.Request(
                webhook,
                data=json.dumps({"text": msg}).encode(),
                headers={"Content-Type": "application/json"},
            )
            urllib.request.urlopen(req, timeout=10)  # noqa: S310 (operator-configured URL)
            return
        except Exception:
            pass

    # 3) Email, if configured (requires Airflow SMTP to be set up).
    to = os.environ.get("ALERT_EMAIL")
    if to:
        try:
            from airflow.utils.email import send_email
            send_email(to=[to], subject=f"[ALERT] {dag_id} failed", html_content=msg)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Default arguments applied to every task in this DAG.
# ---------------------------------------------------------------------------
DEFAULT_ARGS = {
    "owner": "data_engineering",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    # AUDIT-003-M1: notify on failure instead of failing silently.
    "on_failure_callback": alert_on_failure,
}

# ---------------------------------------------------------------------------
# Pipeline-level constants
# ---------------------------------------------------------------------------
DBT_PROJECT_DIR = "/dbt/printtime_dw"          # mounted volume (same path as the dbt service)
# dbt's artifacts land in the airflow-local dir set by DBT_TARGET_PATH in
# docker-compose (the mounted project's target/ isn't writable by airflow,
# and this keeps orchestrated artifacts separate from ad-hoc dbt runs).
DBT_RUN_RESULTS = "/opt/airflow/dbt_artifacts/target/run_results.json"

# Gold targets whose batches the fact models read as their incremental watermark
# (target_table must match the models' queries EXACTLY), plus a summary row for
# the dimension run so every gold load is auditable per ADR-008.
GOLD_BATCH_TARGETS: dict[str, str] = {
    "gold.dimensions": "scd2_merge",
    "gold.fact_retail_sales": "fact_reload",
    "gold.fact_payments": "fact_reload",
    "gold.fact_customer_behavior_snapshot": "snapshot_append",
}

# run_results node name → which gold batch its rows_affected belongs to.
_GOLD_NODE_TO_TARGET = {
    "fact_retail_sales": "gold.fact_retail_sales",
    "fact_payments": "gold.fact_payments",
    "fact_customer_behavior_snapshot": "gold.fact_customer_behavior_snapshot",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _rows_affected_by_model() -> dict[str, int]:
    """Read dbt's target/run_results.json and return {model_name: rows_affected}.

    dbt writes it after every invocation, so read it in the task IMMEDIATELY
    following the dbt run it describes. Missing/odd entries count as 0 —
    row counts are best-effort audit metadata, never a reason to fail a load.
    """
    try:
        with open(DBT_RUN_RESULTS, encoding="utf-8") as fh:
            results = json.load(fh).get("results", [])
    except (OSError, json.JSONDecodeError):
        return {}
    rows: dict[str, int] = {}
    for r in results:
        model = str(r.get("unique_id", "")).rsplit(".", 1)[-1]
        affected = (r.get("adapter_response") or {}).get("rows_affected")
        rows[model] = int(affected) if isinstance(affected, (int, float)) else 0
    return rows


# ---------------------------------------------------------------------------
# Python callables
# ---------------------------------------------------------------------------

def _ingest_oltp_to_bronze(**context: dict) -> None:
    """Extract every configured OLTP table and load it into bronze.

    ingestion.main.run opens/completes its own batch per table in
    audit.etl_batch_control, so no extra bookkeeping is needed here.
    """
    from ingestion.main import run
    from ingestion.utils.config_loader import load_config

    config = load_config()
    tables = config.get("tables", [])
    if not tables:
        raise ValueError("No tables configured in ingestion_config.yml")

    default_strategy = config.get("default_load_strategy", "incremental")
    for table in tables:
        run(
            pipeline_name=PIPELINE_NAME,
            table_name=table["name"],
            strategy=table.get("load_strategy", default_strategy),
        )


def _ingest_fred_to_bronze(**context: dict) -> None:
    """Extract FRED macro series (CPI, PPI) into bronze.econ_indicator.

    Independent API source: it opens/completes its own batch in
    audit.etl_batch_control, so it runs in parallel with the OLTP ingest and
    both must finish before silver builds.
    """
    from ingestion.main import run_fred_ingest

    run_fred_ingest(pipeline_name=PIPELINE_NAME)


def _start_silver_batch(**context: dict) -> int:
    """Open one 'running' batch for the silver dbt run and return its key.

    The key is XCom-pushed (return value) and templated into run_dbt_silver as
    --vars silver_batch_id, so every merged silver row stamps this batch.
    """
    from ingestion.utils.batch_control import start_batch

    batch_key, batch_id = start_batch(
        pipeline_name=PIPELINE_NAME,
        source_system="bronze",
        target_table="silver",
        load_type="incremental_merge",
    )
    print(f"[{PIPELINE_NAME}] silver batch opened: key={batch_key} id={batch_id}")
    return batch_key


def _complete_silver_batch(**context: dict) -> None:
    """Mark the silver batch 'succeeded', with rows merged from run_results."""
    from ingestion.utils.batch_control import complete_batch

    batch_key = context["ti"].xcom_pull(task_ids="start_silver_batch")
    rows = _rows_affected_by_model()
    total = sum(rows.values())
    complete_batch(batch_key=batch_key, rows_extracted=total, rows_inserted=total)
    print(f"[{PIPELINE_NAME}] silver batch {batch_key} succeeded: {total} rows across {len(rows)} models")


def _start_gold_batches(**context: dict) -> dict[str, int]:
    """Open one 'running' batch per gold target; return {target: batch_key}.

    The fact models' watermark reads the last SUCCEEDED batch per target, so
    these rows only advance the watermark once completed after a good run.

    Also pushes a 'gold_vars_json' XCom — the dbt --vars payload mapping each
    target to its TEXT batch_id — so run_dbt_gold can stamp every gold row's
    etl_batch_id with the real batch that wrote it (MED-10). etl_batch_id joins
    to audit.etl_batch_control.batch_id (gold naming convention), so gold stamps
    the text batch_id, not the integer batch_key that silver uses.
    """
    from ingestion.utils.batch_control import start_batch

    keys: dict[str, int] = {}
    batch_ids: dict[str, str] = {}
    for target, load_type in GOLD_BATCH_TARGETS.items():
        batch_key, batch_id = start_batch(
            pipeline_name=PIPELINE_NAME,
            source_system="silver",
            target_table=target,
            load_type=load_type,
        )
        keys[target] = batch_key
        batch_ids[target] = batch_id
    # Each gold model looks up its own target's batch_id from this map. Dims all
    # share the 'gold.dimensions' batch by design (ADR-008); facts use their own.
    context["ti"].xcom_push(
        key="gold_vars_json",
        value=json.dumps({"gold_batch_ids": batch_ids}),
    )
    print(f"[{PIPELINE_NAME}] gold batches opened: {keys}")
    return keys


def _complete_gold_batches(**context: dict) -> None:
    """Mark every gold batch 'succeeded' — this advances the facts' watermark."""
    from ingestion.utils.batch_control import complete_batch

    keys: dict[str, int] = context["ti"].xcom_pull(task_ids="start_gold_batches")
    rows = _rows_affected_by_model()
    dim_total = sum(n for m, n in rows.items() if m.startswith("dim_"))
    for target, batch_key in keys.items():
        node = next((m for m, t in _GOLD_NODE_TO_TARGET.items() if t == target), None)
        total = rows.get(node, 0) if node else dim_total
        complete_batch(batch_key=batch_key, rows_extracted=total, rows_inserted=total)
        print(f"[{PIPELINE_NAME}] gold batch {batch_key} ({target}) succeeded: {total} rows")


def _fail_open_batches(**context: dict) -> None:
    """Close any batch this run left 'running' after a failure.

    Runs only when an upstream task failed (trigger_rule=ONE_FAILED). Without
    it, a crashed run would strand 'running' rows forever — and, worse, a later
    manual fix could complete them and silently advance the facts' watermark.

    The filter is `initiated_by = PIPELINE` (all layers — bronze/silver/gold),
    which is correctly scoped to THIS run because the DAG sets max_active_runs=1
    (MED-11): there is never a concurrent run whose in-flight batches this could
    wrongly fail. This also catches stranded bronze batches (opened inside the
    ingest task, so not available via XCom) that a key-scoped sweep would miss.
    """
    from sqlalchemy import text

    from ingestion.utils.database import get_dw_engine

    engine = get_dw_engine()
    sql = text(
        """
        UPDATE audit.etl_batch_control
        SET batch_status = 'failed',
            batch_end_timestamp = clock_timestamp(),
            error_message = 'closed by fail_open_batches: upstream task failed'
        WHERE batch_status = 'running'
          AND initiated_by = :pipeline
        """
    )
    with engine.begin() as conn:
        closed = conn.execute(sql, {"pipeline": PIPELINE_NAME}).rowcount
    print(f"[{PIPELINE_NAME}] fail_open_batches: closed {closed} stranded batch(es)")


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------

with DAG(
    dag_id=PIPELINE_NAME,
    description="PrintTimeUSA ELT pipeline: Extract → Bronze → Silver → Gold → Tests",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="@daily",
    catchup=False,
    # MED-11: a watermark-driven pipeline must never run concurrently — two runs
    # would share watermarks and delete+insert the same fact rows. This also makes
    # _fail_open_batches correct: with a single active run, its
    # initiated_by=PIPELINE filter only ever matches THIS run's stranded batches.
    max_active_runs=1,
    tags=["elt", "printtime", "bronze", "silver", "gold"],
    doc_md=__doc__,
) as dag:

    # ── Bookend tasks ────────────────────────────────────────────────────────
    start_pipeline = EmptyOperator(task_id="start_pipeline")
    end_pipeline   = EmptyOperator(task_id="end_pipeline")

    # ── 1. Extract OLTP data and load into bronze (Python) ───────────────────
    ingest_oltp_to_bronze = PythonOperator(
        task_id="ingest_oltp_to_bronze",
        python_callable=_ingest_oltp_to_bronze,
        doc_md="Extracts every configured OLTP table into bronze. Logs one batch per table.",
    )

    ingest_fred_to_bronze = PythonOperator(
        task_id="ingest_fred_to_bronze",
        python_callable=_ingest_fred_to_bronze,
        doc_md="Extracts FRED macro series (CPI, PPI) into bronze.econ_indicator (API source).",
    )

    # ── 2. Silver: open batch → dbt run (with the real batch id) → complete ──
    start_silver_batch = PythonOperator(
        task_id="start_silver_batch",
        python_callable=_start_silver_batch,
        doc_md="Opens the silver batch in audit.etl_batch_control; key goes to XCom.",
    )

    # NOTE: plain string concatenation, not an f-string — the {{ }} must survive
    # for Airflow's Jinja templating of the XCom pull.
    run_dbt_silver = BashOperator(
        task_id="run_dbt_silver",
        bash_command=(
            "cd " + DBT_PROJECT_DIR + " && "
            "dbt run --select silver --profiles-dir " + DBT_PROJECT_DIR + " "
            "--no-version-check "
            "--vars '{silver_batch_id: {{ ti.xcom_pull(task_ids=\"start_silver_batch\") }}}'"
        ),
        doc_md="Runs the 20 silver models, stamping rows with the real silver_batch_id.",
    )

    complete_silver_batch = PythonOperator(
        task_id="complete_silver_batch",
        python_callable=_complete_silver_batch,
        doc_md="Marks the silver batch succeeded with rows merged (from run_results.json).",
    )

    # ── 3. Gold: open batches → dbt run → complete (advances fact watermark) ─
    start_gold_batches = PythonOperator(
        task_id="start_gold_batches",
        python_callable=_start_gold_batches,
        doc_md="Opens one batch per gold target (dims summary + the three facts).",
    )

    run_dbt_gold = BashOperator(
        task_id="run_dbt_gold",
        # String concatenation (not an f-string) so the {{ ... }} survives to
        # Airflow's Jinja templating. --vars carries the {target: batch_id} map
        # opened above so every gold row stamps its real etl_batch_id (MED-10).
        bash_command=(
            "cd " + DBT_PROJECT_DIR + " && "
            "dbt run --select gold --profiles-dir " + DBT_PROJECT_DIR + " --no-version-check "
            "--vars '{{ ti.xcom_pull(task_ids=\"start_gold_batches\", key=\"gold_vars_json\") }}'"
        ),
        doc_md="Runs the 14 gold objects (SCD2 dims, facts, date views), stamping each row's etl_batch_id.",
    )

    complete_gold_batches = PythonOperator(
        task_id="complete_gold_batches",
        python_callable=_complete_gold_batches,
        doc_md="Marks gold batches succeeded — the facts' incremental watermark advances here.",
    )

    # ── 4. dbt: data quality tests — GATE the gold watermark (HIGH-7) ────────
    # Runs BEFORE complete_gold_batches, so a failing test leaves the gold
    # batches 'running' (never 'succeeded') and the facts' watermark does not
    # advance — the next run reprocesses instead of skipping bad data.
    # DBT_TARGET_PATH is redirected here so `dbt test` does not overwrite the
    # gold run's run_results.json, which complete_gold_batches reads next for its
    # row counts.
    run_dbt_tests = BashOperator(
        task_id="run_dbt_tests",
        bash_command=(
            "cd " + DBT_PROJECT_DIR + " && "
            "DBT_TARGET_PATH=/opt/airflow/dbt_artifacts/test_target "
            "dbt test --profiles-dir " + DBT_PROJECT_DIR + " --no-version-check"
        ),
        doc_md=(
            "Runs all dbt tests on silver and gold. Gates the gold watermark: "
            "it runs before complete_gold_batches, so a failure holds the batches "
            "'running' and the watermark does not advance."
        ),
    )

    # ── 5. Failure sweeper ──────────────────────────────────────────────────
    fail_open_batches = PythonOperator(
        task_id="fail_open_batches",
        python_callable=_fail_open_batches,
        trigger_rule=TriggerRule.ONE_FAILED,
        doc_md="Only on failure: marks this pipeline's stranded 'running' batches as failed.",
    )

    # ── Task dependencies ────────────────────────────────────────────────────
    # Tests run AFTER run_dbt_gold but BEFORE complete_gold_batches (HIGH-7):
    # validation must gate the watermark commit, not trail it. If a test fails,
    # complete_gold_batches is skipped (upstream_failed), the gold batches stay
    # 'running', fail_open_batches marks them 'failed', and the facts' watermark
    # never advances — so the next run reprocesses rather than skipping bad data.
    #
    # complete_silver_batch stays before the tests on purpose: silver's watermark
    # is row-based (each model reads max(silver_bronze_batch_id) from its own
    # table), so it advances when run_dbt_silver writes rows regardless of the
    # audit batch status. Its completion is bookkeeping, not a watermark gate,
    # so there is nothing for the tests to hold back there.
    main_chain = [
        ingest_oltp_to_bronze,
        start_silver_batch,
        run_dbt_silver,
        complete_silver_batch,
        start_gold_batches,
        run_dbt_gold,
        run_dbt_tests,
        complete_gold_batches,
    ]

    start_pipeline >> main_chain[0]
    for upstream, downstream in zip(main_chain, main_chain[1:]):
        upstream >> downstream
    main_chain[-1] >> end_pipeline

    # FRED bronze load runs in parallel with the OLTP ingest; silver waits for both.
    start_pipeline >> ingest_fred_to_bronze >> start_silver_batch
    ingest_fred_to_bronze >> fail_open_batches

    # The sweeper watches every batch-holding step; ONE_FAILED means it is
    # skipped on a clean run and fires as soon as any of these fails.
    main_chain >> fail_open_batches
