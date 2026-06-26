-- =====================================================================
-- PrintTimeUSA Data Warehouse | Audit Schema
-- 003_create_audit_indexes.sql
-- Lookup indexes for batch monitoring and audit-trail queries.
-- (batch_id already has a UNIQUE constraint / index.)
-- =====================================================================

SET search_path = audit, public;


-- etl_batch_control
CREATE INDEX IF NOT EXISTS idx_etl_batch_control_target_table ON audit.etl_batch_control (target_table);
CREATE INDEX IF NOT EXISTS idx_etl_batch_control_batch_status ON audit.etl_batch_control (batch_status);
CREATE INDEX IF NOT EXISTS idx_etl_batch_control_source_system_target_table ON audit.etl_batch_control (source_system, target_table);

-- audit_log
CREATE INDEX IF NOT EXISTS idx_audit_log_table_name ON audit.audit_log (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON audit.audit_log (changed_at);
