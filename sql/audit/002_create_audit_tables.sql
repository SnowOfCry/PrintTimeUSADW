-- =====================================================================
-- PrintTimeUSA Data Warehouse | Audit Schema
-- 002_create_audit_tables.sql
-- audit.etl_batch_control — one row per ETL batch (watermark + run stats).
-- audit.audit_log         — generic insert-only row-change audit trail.
-- Surrogate keys = <entity>_key/_id (GENERATED ALWAYS AS IDENTITY).
-- =====================================================================

SET search_path = audit, public;


-- ---------------------------------------------------------------------
-- audit.etl_batch_control
-- One row per ETL batch across any layer. Drives incremental watermarks
-- and records load outcome/statistics. batch_id is the external UNIQUE
-- batch identifier used by the pipeline.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.etl_batch_control (
    batch_key INTEGER GENERATED ALWAYS AS IDENTITY,
    batch_id VARCHAR(50) NOT NULL,
    source_system VARCHAR(50),
    target_table VARCHAR(100),
    load_type VARCHAR(20),
    watermark_column VARCHAR(100),
    watermark_value_start VARCHAR(100),
    watermark_value_end VARCHAR(100),
    batch_status VARCHAR(20),
    batch_start_timestamp TIMESTAMP,
    batch_end_timestamp TIMESTAMP,
    rows_extracted INTEGER,
    rows_inserted INTEGER,
    rows_updated INTEGER,
    rows_deleted INTEGER,
    rows_rejected INTEGER,
    error_message VARCHAR(2000),
    retry_count INTEGER NOT NULL DEFAULT 0,
    initiated_by VARCHAR(100),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT pk_etl_batch_control PRIMARY KEY (batch_key),
    CONSTRAINT uq_etl_batch_control_batch_id UNIQUE (batch_id)
);
COMMENT ON TABLE audit.etl_batch_control IS 'ETL batch control / watermark table. One row per batch with load type, watermark window, status, and row statistics.';
COMMENT ON COLUMN audit.etl_batch_control.batch_key IS 'Surrogate key (identity).';
COMMENT ON COLUMN audit.etl_batch_control.batch_id IS 'External batch identifier (UNIQUE). Referenced by etl_batch_id across layers.';
COMMENT ON COLUMN audit.etl_batch_control.load_type IS 'Load strategy for the batch (e.g. incremental_append, incremental_merge, full).';
COMMENT ON COLUMN audit.etl_batch_control.batch_status IS 'Run status (e.g. running, succeeded, failed).';

-- ---------------------------------------------------------------------
-- audit.audit_log
-- Generic, insert-only audit trail of row-level changes captured by the
-- pipeline or DB triggers. Append-only: never updated or deleted.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.audit_log (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY,
    table_name VARCHAR(100) NOT NULL,
    operation_type VARCHAR(10) NOT NULL,
    record_key VARCHAR(100),
    old_row JSONB,
    new_row JSONB,
    changed_columns JSONB,
    change_reason VARCHAR(500),
    changed_by_app_user VARCHAR(100),
    changed_by_db_user VARCHAR(100) DEFAULT current_user,
    changed_at TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
    etl_batch_id VARCHAR(50),
    source_system VARCHAR(50),
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id)
);
COMMENT ON TABLE audit.audit_log IS 'Generic insert-only audit trail of row-level changes (INSERT/UPDATE/DELETE) with before/after JSONB snapshots.';
COMMENT ON COLUMN audit.audit_log.audit_id IS 'Surrogate key (identity).';
COMMENT ON COLUMN audit.audit_log.operation_type IS 'Change type: INSERT, UPDATE, or DELETE.';
COMMENT ON COLUMN audit.audit_log.record_key IS 'Business/primary key of the changed row in table_name.';
COMMENT ON COLUMN audit.audit_log.changed_columns IS 'JSONB list of columns that changed (for UPDATE).';
