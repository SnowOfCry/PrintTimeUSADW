-- =====================================================================
-- PrintTimeUSA Data Warehouse | Silver Layer
-- 001_create_silver_schema.sql
-- Cleaned, standardized, deduplicated, conformed layer.
-- Medallion: bronze -> silver -> gold. Load strategy: INCREMENTAL_MERGE.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS silver;

COMMENT ON SCHEMA silver IS
  'Cleaned/conformed layer. One current clean row per business key (merge upsert). '
  'Standardizes text/status/amounts, deduplicates Bronze append-only history, keeps lineage to Bronze. '
  'No Gold surrogate keys, facts, dimensions, or final metrics.';
