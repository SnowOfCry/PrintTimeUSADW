-- =============================================================================
-- gold.bi_dim_store — STORE / location dimension for BI (ADR-017)
-- One row per store version (SCD2). store_state is the full state name.
-- Audit/DQ/SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    store_key,
    store_id,
    store_name,
    store_city,
    store_state,
    store_region,
    store_type,
    open_date,
    is_current
from {{ ref('dim_store') }}
