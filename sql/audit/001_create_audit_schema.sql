-- =====================================================================
-- PrintTimeUSA Data Warehouse | Audit Schema
-- 001_create_audit_schema.sql
-- Governance/control layer: ETL batch control (watermarks) and a generic
-- insert-only audit trail. These are operational metadata tables, NOT
-- analytical Gold tables, so they live in their own audit schema.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA audit IS
  'Governance/control layer. Holds ETL batch control (watermarks, run stats) '
  'and a generic insert-only audit trail. Cross-cutting over bronze/silver/gold; '
  'not part of the dimensional model.';
