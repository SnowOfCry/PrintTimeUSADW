"""
example_elt_pipeline.py
-----------------------
Skeleton ELT pipeline DAG for PrintTimeUSA Data Warehouse.

Flow:
    start_pipeline
        → extract_oltp_data          (Python: reads from OLTP source)
        → load_bronze                (Python: loads raw data into bronze schema)
        → run_dbt_silver             (dbt: cleans + standardizes bronze → silver)
        → run_dbt_gold               (dbt: builds dimensions + facts silver → gold)
        → run_dbt_tests              (dbt: data quality tests on silver + gold)
        → update_control_logs        (Python: finalizes batch log record)
    end_pipeline

Replace the BashOperator placeholders with real source credentials and table
names as you extend this pipeline.
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
PIPELINE_NAME = "example_elt_pipeline"
DBT_PROJECT_DIR = "/dbt/printtime_dw"   # mounted volume path inside dbt container
DBT_PROFILES_DIR = "/dbt/printtime_dw"


# ---------------------------------------------------------------------------
# Python callables
# ---------------------------------------------------------------------------

def _extract_oltp_data(**context: dict) -> None:
    """
    Extract raw data from the OLTP source system.

    Replace this placeholder with a real call to ingestion/extract/oltp_extractor.py.
    The extractor should:
      - Connect to the OLTP source using environment-based credentials.
      - Use the watermark from control.elt_watermark for incremental loads.
      - Return (or store) the raw records for the loader.
    """
    # TODO: import and call OLTPExtractor from ingestion layer
    # from ingestion.extract.oltp_extractor import OLTPExtractor
    # extractor = OLTPExtractor(source_name="oltp_printtime", pipeline_name=PIPELINE_NAME)
    # rows = extractor.extract_table(table_name="orders", watermark_column="updated_at")
    # context["ti"].xcom_push(key="extracted_rows", value=len(rows))
    print(f"[{PIPELINE_NAME}] PLACEHOLDER: extract_oltp_data — wire in OLTPExtractor here.")


def _load_bronze(**context: dict) -> None:
    """
    Load extracted raw data into the bronze schema.

    Replace this placeholder with a real call to ingestion/load/bronze_loader.py.
    The loader should:
      - Accept a DataFrame or list of dicts.
      - Write to bronze.<target_table> with no business transformations.
      - Log results to control.elt_batch_log.
    """
    # TODO: import and call BronzeLoader from ingestion layer
    # from ingestion.load.bronze_loader import BronzeLoader
    # loader = BronzeLoader(pipeline_name=PIPELINE_NAME, target_table="orders")
    # loader.load_dataframe_to_bronze(df=extracted_df)
    print(f"[{PIPELINE_NAME}] PLACEHOLDER: load_bronze — wire in BronzeLoader here.")


def _update_control_logs(**context: dict) -> None:
    """
    Mark the batch as complete (success or failure) in control.elt_batch_log.

    In production, retrieve the batch_id from XCom (set during load_bronze)
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

    # ── 1. Extract OLTP data (Python) ────────────────────────────────────────
    extract_oltp_data = PythonOperator(
        task_id="extract_oltp_data",
        python_callable=_extract_oltp_data,
        doc_md="Reads raw data from the OLTP source using watermarks for incremental loads.",
    )

    # ── 2. Load raw data into bronze (Python) ────────────────────────────────
    load_bronze = PythonOperator(
        task_id="load_bronze",
        python_callable=_load_bronze,
        doc_md="Writes extracted raw data to the bronze schema. No transformations applied.",
    )

    # ── 3. dbt: silver layer ─────────────────────────────────────────────────
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

    # ── 4. dbt: gold layer ───────────────────────────────────────────────────
    run_dbt_gold = BashOperator(
        task_id="run_dbt_gold",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select gold --profiles-dir {DBT_PROFILES_DIR} --no-version-check"
        ),
        doc_md="Runs dbt gold models: builds star-schema dimensions and fact tables.",
    )

    # ── 5. dbt: data quality tests ───────────────────────────────────────────
    run_dbt_tests = BashOperator(
        task_id="run_dbt_tests",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt test --profiles-dir {DBT_PROFILES_DIR} --no-version-check"
        ),
        doc_md="Runs dbt tests on silver and gold models. Fails the DAG if tests do not pass.",
    )

    # ── 6. Update pipeline control logs ─────────────────────────────────────
    update_control_logs = PythonOperator(
        task_id="update_control_logs",
        python_callable=_update_control_logs,
        doc_md="Finalizes the batch record in control.elt_batch_log and updates watermarks.",
    )

    # ── Task dependencies ────────────────────────────────────────────────────
    (
        start_pipeline
        >> extract_oltp_data
        >> load_bronze
        >> run_dbt_silver
        >> run_dbt_gold
        >> run_dbt_tests
        >> update_control_logs
        >> end_pipeline
    )
