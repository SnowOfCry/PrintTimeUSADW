-- =============================================================================
-- 001_create_schemas.sql
-- Creates the layered data warehouse schemas for the PrintTimeUSA ELT pipeline.
-- =============================================================================

-- Bronze: raw data loaded directly from OLTP sources with no transformation.
CREATE SCHEMA IF NOT EXISTS bronze;
COMMENT ON SCHEMA bronze IS 'Raw layer: data loaded as-is from OLTP source systems by Python ingestion.';

-- Silver: cleaned, standardized, and deduplicated data produced by dbt.
CREATE SCHEMA IF NOT EXISTS silver;
COMMENT ON SCHEMA silver IS 'Conformed layer: cleaned and standardized data produced by dbt silver models.';

-- Gold: dimensional/fact models and business-ready analytics produced by dbt.
CREATE SCHEMA IF NOT EXISTS gold;
COMMENT ON SCHEMA gold IS 'Analytical layer: star-schema dimensions and facts produced by dbt gold models.';

-- Audit: governance/control layer — ETL batch control (watermarks, run stats)
-- and a generic insert-only change/audit trail. (Replaces the former 'control'
-- schema; batch + watermark tracking now lives in audit.etl_batch_control.)
CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA audit IS 'Governance layer: ETL batch control (watermarks, run stats) and generic insert-only audit trail.';
