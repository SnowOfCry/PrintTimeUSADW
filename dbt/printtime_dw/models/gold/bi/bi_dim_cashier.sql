-- =============================================================================
-- gold.bi_dim_cashier — CASHIER / employee dimension for BI (ADR-017)
-- One row per cashier version (SCD2); the assigned store is denormalized on the
-- row. is_active is a 'Yes'/'No' label. Audit/DQ/SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    cashier_key,
    cashier_id,
    cashier_first_name,
    cashier_last_name,
    cashier_full_name,
    is_active,
    store_id,
    store_name,
    is_current
from {{ ref('dim_cashier') }}
