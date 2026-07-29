-- =============================================================================
-- gold.bi_fact_sales — SALES fact for BI (ADR-017)
-- Grain: one row per invoice line. Foreign keys (for Power BI relationships) +
-- the degenerate invoice_number + additive measures. Audit/DQ plumbing hidden.
--
-- No ratio columns by design: gross margin % is a DAX measure
-- ( SUM(gross_profit) / SUM(sales_amount) ), never a row-level average — that
-- would aggregate incorrectly. Only additive measures live here.
-- Every *_key resolves to a dimension row (including the -1 member, ADR-011),
-- so relationships have no blanks.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    -- surrogate key
    sales_line_key,

    -- foreign keys → bi_dim_*
    date_key,
    product_key,
    customer_key,
    store_key,
    cashier_key,
    invoice_key,

    -- degenerate dimension
    invoice_number,

    -- additive measures
    sales_qty,
    unit_price,
    unit_cost,
    sales_amount,
    sales_cost,
    gross_profit
from {{ ref('fact_retail_sales') }}
