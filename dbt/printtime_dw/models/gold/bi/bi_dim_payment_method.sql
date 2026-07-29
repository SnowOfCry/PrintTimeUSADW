-- =============================================================================
-- gold.bi_dim_payment_method — PAYMENT METHOD dimension for BI (ADR-017)
-- One row per method version (SCD2): cash, cards, check, ACH, etc.
-- Audit/DQ/SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    payment_method_key,
    method_code,
    method_name,
    method_type,
    is_active,
    is_current
from {{ ref('dim_payment_method') }}
