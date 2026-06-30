-- =============================================================================
-- 002_create_audit_tables.sql
-- Creates the governance/control tables in the audit schema. Source-agnostic
-- and reused by every ELT pipeline run. Mirrors sql/audit/002 + 003 so a fresh
-- container bootstraps the same audit objects deployed by the standalone DDL.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- audit.etl_batch_control
-- One row per ETL batch (any layer). Drives incremental watermarks (embedded
-- watermark window) and records load outcome/statistics. batch_id is the
-- external UNIQUE identifier; batch_key is the numeric surrogate that
-- bronze_batch_id references.
-- -----------------------------------------------------------------------------
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
COMMENT ON COLUMN audit.etl_batch_control.batch_key IS 'Numeric surrogate key (identity). Referenced by bronze_batch_id.';
COMMENT ON COLUMN audit.etl_batch_control.batch_id IS 'External batch identifier (UNIQUE).';

CREATE INDEX IF NOT EXISTS idx_etl_batch_control_target_table ON audit.etl_batch_control (target_table);
CREATE INDEX IF NOT EXISTS idx_etl_batch_control_batch_status ON audit.etl_batch_control (batch_status);
CREATE INDEX IF NOT EXISTS idx_etl_batch_control_source_system_target_table ON audit.etl_batch_control (source_system, target_table);

-- -----------------------------------------------------------------------------
-- audit.audit_log
-- Generic, insert-only audit trail of row-level changes. Append-only.
-- -----------------------------------------------------------------------------
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

CREATE INDEX IF NOT EXISTS idx_audit_log_table_name ON audit.audit_log (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON audit.audit_log (changed_at);
