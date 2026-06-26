-- =====================================================================
-- PrintTimeUSA Data Warehouse | Bronze Layer
-- 001_create_bronze_schema.sql
-- Creates the bronze schema (raw/lightly standardized landing layer).
-- Medallion architecture: bronze -> silver -> gold
-- Load strategy: INCREMENTAL_APPEND (append-only; no update/delete/merge).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

COMMENT ON SCHEMA bronze IS
  'Raw landing layer. Append-only. One row per extracted source-row version. '
  'No SCD2, no facts, no dimensions, no business metrics. Feeds the silver layer.';
