"""
printtime_elt_pipeline.py
-------------------------
PrintTimeUSA Data Warehouse — end-to-end ELT pipeline.

Flow:
    start_pipeline
        → ingest_oltp_to_bronze      (Python: extract from OLTP → load bronze, per table)
        → run_dbt_silver             (dbt: cleans + standardizes bronze → silver)
        → run_dbt_gold               (dbt: builds dimensions + facts silver → gold)
        → run_dbt_tests              (dbt: data quality tests on silver + gold)
        → update_control_logs        (Python: finalizes batch log record)
    end_pipeline

The ingestion step reads the table list from ingestion/config/ingestion_config.yml
and runs the extract + bronze load for each table using the ingestion package.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator

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
}

# ---------------------------------------------------------------------------
# Pipeline-level constants
# (Replace hardcoded values with Airflow Variables or Connections in production)
# ---------------------------------------------------------------------------
PIPELINE_NAME = "printtime_elt_pipeline"
DBT_PROJECT_DIR = "/dbt/printtime_dw"   # mounted volume path inside dbt container
DBT_PROFILES_DIR = "/dbt/printtime_dw"


# ---------------------------------------------------------------------------
# Python callables
# ---------------------------------------------------------------------------

def _ingest_oltp_to_bronze(**context: dict) -> None:
    """
    Extract every configured OLTP table and load it into the bronze schema.

    Reads the table list (name, load_strategy) from ingestion_config.yml and
    runs the tested extract + load path (ingestion.main.run) for each table.
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


def _update_control_logs(**context: dict) -> None:
    """
    Mark the batch as complete (success or failure) in control.elt_batch_log.

    In production, retrieve the batch_id from XCom (set during ingestion)
    and update status + ended_at.
    """
    # TODO: import and call watermark + batch log utilities
    # from ingestion.utils.watermark import update_watermark
    # update_watermark(pipeline_name=PIPELINE_NAME, ...)
    print(f"[{PIPELINE_NAME}] PLACEHOLDER: update_control_logs — finalize batch record here.")


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------

with DAG(
    dag_id=PIPELINE_NAME,
    description="PrintTimeUSA ELT pipeline: Extract → Bronze → Silver → Gold → Tests",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="@daily",          # Change to your preferred schedule (cron or preset)
    catchup=False,
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
        doc_md="Extracts every configured OLTP table and loads it into bronze. No transformations.",
    )

    # ── 2. dbt: silver layer ─────────────────────────────────────────────────
    # BashOperator runs dbt inside the airflow container (dbt must be installed there),
    # OR swap for DockerOperator to run in the dedicated dbt container.
    run_dbt_silver = BashOperator(
        task_id="run_dbt_silver",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select silver --profiles-dir {DBT_PROFILES_DIR} --no-version-check"
        ),
        doc_md="Runs dbt silver models: cleans, standardizes, and deduplicates bronze data.",
    )

    # ── 3. dbt: gold layer ───────────────────────────────────────────────────
    run_dbt_gold = BashOperator(
        task_id="run_dbt_gold",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select gold --profiles-dir {DBT_PROFILES_DIR} --no-version-check"
        ),
        doc_md="Runs dbt gold models: builds star-schema dimensions and fact tables.",
    )

    # ── 4. dbt: data quality tests ───────────────────────────────────────────
    run_dbt_tests = BashOperator(
        task_id="run_dbt_tests",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt test --profiles-dir {DBT_PROFILES_DIR} --no-version-check"
        ),
        doc_md="Runs dbt tests on silver and gold models. Fails the DAG if tests do not pass.",
    )

    # ── 5. Update pipeline control logs ─────────────────────────────────────
    update_control_logs = PythonOperator(
        task_id="update_control_logs",
        python_callable=_update_control_logs,
        doc_md="Finalizes the batch record in control.elt_batch_log and updates watermarks.",
    )

    # ── Task dependencies ────────────────────────────────────────────────────
    (
        start_pipeline
        >> ingest_oltp_to_bronze
        >> run_dbt_silver
        >> run_dbt_gold
        >> run_dbt_tests
        >> update_control_logs
        >> end_pipeline
    )
