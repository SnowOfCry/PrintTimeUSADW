-- Databricks audit tables (auto-translated from sql/audit/002_create_audit_tables.sql)
-- CREATE IF NOT EXISTS: safe to re-run; will NOT drop existing sample data.

CREATE TABLE IF NOT EXISTS printtime_dw.audit.etl_batch_control (
    batch_key INT,
    batch_id STRING,
    source_system STRING,
    target_table STRING,
    load_type STRING,
    watermark_column STRING,
    watermark_value_start STRING,
    watermark_value_end STRING,
    batch_status STRING,
    batch_start_timestamp TIMESTAMP,
    batch_end_timestamp TIMESTAMP,
    rows_extracted INT,
    rows_inserted INT,
    rows_updated INT,
    rows_deleted INT,
    rows_rejected INT,
    error_message STRING,
    retry_count INT,
    initiated_by STRING,
    etl_load_timestamp TIMESTAMP
);

CREATE TABLE IF NOT EXISTS printtime_dw.audit.audit_log (
    audit_id BIGINT,
    table_name STRING,
    operation_type STRING,
    record_key STRING,
    old_row STRING,
    new_row STRING,
    changed_columns STRING,
    change_reason STRING,
    changed_by_app_user STRING,
    changed_by_db_user STRING,
    changed_at TIMESTAMP,
    etl_batch_id STRING,
    source_system STRING
);
