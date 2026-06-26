-- =====================================================================
-- PrintTimeUSA Data Warehouse | Gold Layer
-- 001_create_gold_schema.sql
-- Curated dimensional layer (Kimball star schema): dimensions, facts,
-- a conformed date dimension, and role-playing date views.
-- Medallion architecture: bronze -> silver -> gold.
-- Load strategy: SCD2 dimensions (merge) + insert/refresh facts.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gold;

COMMENT ON SCHEMA gold IS
  'Curated analytics layer. Kimball star schema built from Silver. '
  'dim_ tables (SCD2 except dim_payment_type/dim_date), fact_ tables (no SCD2), '
  'a conformed dim_date, and vw_ role-playing date views. '
  'Surrogate keys (_key, identity); natural/business keys (_id). '
  'Audit/control tables live in the audit schema, not here.';
