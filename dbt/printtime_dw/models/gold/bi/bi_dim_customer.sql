-- =============================================================================
-- gold.bi_dim_customer — CUSTOMER dimension for BI (ADR-017)
-- One row per customer version (SCD2). customer_city_state is the ready-made
-- "City, State" label. customer_county is 'Not Provided' (ADR-014). Audit/DQ/
-- SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    customer_key,
    customer_id,
    customer_name,
    customer_street_address,
    customer_city,
    customer_county,
    customer_state,
    customer_city_state,
    first_order_date_key,
    is_current
from {{ ref('dim_customer') }}
