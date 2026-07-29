-- =============================================================================
-- gold.bi_dim_payment_type — PAYMENT TYPE dimension for BI (ADR-017)
-- Type 1 dimension: deposit, balance, full, refund, adjustment. Plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    payment_type_key,
    type_code,
    type_name,
    description
from {{ ref('dim_payment_type') }}
