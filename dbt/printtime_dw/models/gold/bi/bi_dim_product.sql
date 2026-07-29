-- =============================================================================
-- gold.bi_dim_product — PRODUCT dimension for BI (ADR-017)
-- One row per product version (SCD2); facts point to the version in effect for
-- each sale via product_key. is_current lets a report filter to current
-- attributes; audit/DQ/SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    product_key,
    sku_number,
    product_description,
    brand_description,
    category_description,
    department_number,
    department_description,
    markup,
    standard_price,
    local_made_indicator,
    is_current
from {{ ref('dim_product') }}
