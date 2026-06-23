-- =============================================================================
-- 002_create_control_tables.sql
-- Creates generic pipeline tracking tables in the control schema.
-- These tables are source-agnostic and reused by every ELT pipeline run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- control.elt_batch_log
-- One row per pipeline execution attempt. Tracks status, record counts, errors.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS control.elt_batch_log (
    batch_id            BIGSERIAL       PRIMARY KEY,
    pipeline_name       VARCHAR(200)    NOT NULL,           -- logical pipeline identifier
    source_name         VARCHAR(200)    NOT NULL,           -- source system name (e.g. 'oltp_printtime')
    target_schema       VARCHAR(100)    NOT NULL,           -- destination schema (always 'bronze' for Python loads)
    target_table        VARCHAR(200)    NOT NULL,           -- destination table name
    load_strategy       VARCHAR(50)     NOT NULL            -- 'full_load' | 'incremental' | 'upsert'
                        CHECK (load_strategy IN ('full_load', 'incremental', 'upsert')),
    status              VARCHAR(50)     NOT NULL DEFAULT 'running'
                        CHECK (status IN ('running', 'success', 'failed', 'skipped')),
    started_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    ended_at            TIMESTAMPTZ,
    records_extracted   BIGINT          DEFAULT 0,
    records_loaded      BIGINT          DEFAULT 0,
    records_inserted    BIGINT          DEFAULT 0,
    records_updated     BIGINT          DEFAULT 0,
    records_rejected    BIGINT          DEFAULT 0,
    error_message       TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  control.elt_batch_log                  IS 'Tracks every ELT pipeline execution with status and record counts.';
COMMENT ON COLUMN control.elt_batch_log.batch_id         IS 'Surrogate key auto-generated for each run.';
COMMENT ON COLUMN control.elt_batch_log.pipeline_name    IS 'Logical name of the Airflow DAG or ingestion job.';
COMMENT ON COLUMN control.elt_batch_log.source_name      IS 'Source system identifier (e.g. oltp_printtime, api_xyz).';
COMMENT ON COLUMN control.elt_batch_log.target_schema    IS 'Destination PostgreSQL schema.';
COMMENT ON COLUMN control.elt_batch_log.target_table     IS 'Destination PostgreSQL table.';
COMMENT ON COLUMN control.elt_batch_log.load_strategy    IS 'One of: full_load, incremental, upsert.';
COMMENT ON COLUMN control.elt_batch_log.status           IS 'Current batch status: running | success | failed | skipped.';
COMMENT ON COLUMN control.elt_batch_log.records_rejected IS 'Rows that failed validation or type coercion during load.';
COMMENT ON COLUMN control.elt_batch_log.error_message    IS 'Populated on failure with Python exception message or SQL error.';

-- Index for common query patterns
CREATE INDEX IF NOT EXISTS idx_elt_batch_log_pipeline   ON control.elt_batch_log (pipeline_name, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_elt_batch_log_status     ON control.elt_batch_log (status);
CREATE INDEX IF NOT EXISTS idx_elt_batch_log_target     ON control.elt_batch_log (target_schema, target_table);


-- -----------------------------------------------------------------------------
-- control.elt_watermark
-- One row per source table, tracking the high-water mark for incremental loads.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS control.elt_watermark (
    watermark_id                BIGSERIAL       PRIMARY KEY,
    pipeline_name               VARCHAR(200)    NOT NULL,
    source_name                 VARCHAR(200)    NOT NULL,   -- source system name
    source_table                VARCHAR(200)    NOT NULL,   -- fully qualified source table
    target_schema               VARCHAR(100)    NOT NULL,
    target_table                VARCHAR(200)    NOT NULL,
    watermark_column            VARCHAR(200)    NOT NULL,   -- column used as high-water mark (e.g. updated_at)
    last_watermark_value        TEXT,                       -- stored as text; cast to correct type at runtime
    last_successful_batch_id    BIGINT          REFERENCES control.elt_batch_log (batch_id),
    is_active                   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  control.elt_watermark                           IS 'High-water mark registry for incremental ELT loads.';
COMMENT ON COLUMN control.elt_watermark.watermark_id             IS 'Surrogate key.';
COMMENT ON COLUMN control.elt_watermark.pipeline_name            IS 'Owning pipeline/DAG name.';
COMMENT ON COLUMN control.elt_watermark.source_table             IS 'Fully qualified source table (schema.table or db.schema.table).';
COMMENT ON COLUMN control.elt_watermark.watermark_column         IS 'Column name used for incremental filtering (e.g. updated_at, row_version).';
COMMENT ON COLUMN control.elt_watermark.last_watermark_value     IS 'Highest seen value of watermark_column in the last successful run.';
COMMENT ON COLUMN control.elt_watermark.last_successful_batch_id IS 'FK to the most recent successful batch in elt_batch_log.';
COMMENT ON COLUMN control.elt_watermark.is_active                IS 'FALSE disables incremental extraction for this source table.';

-- Unique constraint: one watermark row per pipeline + source table
CREATE UNIQUE INDEX IF NOT EXISTS uq_elt_watermark_pipeline_src
    ON control.elt_watermark (pipeline_name, source_name, source_table);

CREATE INDEX IF NOT EXISTS idx_elt_watermark_active
    ON control.elt_watermark (is_active);
