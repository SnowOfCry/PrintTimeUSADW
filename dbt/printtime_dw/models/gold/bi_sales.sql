-- =============================================================================
-- gold.bi_sales  — BI serving view (ADR-017)
-- Grain:  one row per invoice line (same as fact_retail_sales).
-- Purpose: report-ready sales, pre-joined one hop to every dimension with
--          business-friendly names, so Power BI / Tableau consume clean
--          semantics instead of re-deriving joins and margin per tool.
-- Reads:  gold only (ADR-001). Joins on the surrogate keys the fact stored, so
--          each line keeps the product/store/customer VERSION in effect for it
--          (standard star join — no is_current filter; that is the fact's job).
-- Powers: "margin by department & month", "which store is trending".
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    -- ── when ──────────────────────────────────────────────────────────────
    d.date                          as sale_date,
    d.calendar_year                 as sale_year,
    d.calendar_quarter              as sale_quarter,
    d.calendar_year_quarter         as sale_year_quarter,
    d.calendar_month_name           as sale_month_name,
    d.calendar_year_month           as sale_year_month,
    d.day_of_week                   as sale_day_of_week,
    d.weekday_indicator             as sale_weekday_indicator,
    d.holiday_indicator             as sale_holiday_indicator,

    -- ── what ──────────────────────────────────────────────────────────────
    p.sku_number                    as product_sku,
    p.product_description           as product,
    p.brand_description             as brand,
    p.category_description          as category,
    p.department_description        as department,
    p.local_made_indicator          as local_made,

    -- ── who / where ───────────────────────────────────────────────────────
    c.customer_name                 as customer,
    c.customer_city_state           as customer_city_state,
    c.customer_state                as customer_state,
    s.store_name                    as store,
    s.store_city                    as store_city,
    s.store_state                   as store_state,
    s.store_region                  as store_region,
    s.store_type                    as store_type,
    ca.cashier_full_name            as cashier,
    f.invoice_number                as invoice_number,

    -- ── measures ──────────────────────────────────────────────────────────
    f.sales_qty                     as quantity,
    f.unit_price                    as unit_price,
    f.unit_cost                     as unit_cost,
    f.sales_amount                  as sales_amount,
    f.sales_cost                    as sales_cost,
    f.gross_profit                  as gross_profit,
    -- margin as a ratio (0–1); format as % in the BI tool. NULL-safe on $0 lines.
    round(f.gross_profit / nullif(f.sales_amount, 0), 4) as gross_margin_pct

from {{ ref('fact_retail_sales') }} f
join {{ ref('dim_date') }}     d  on d.date_key     = f.date_key
join {{ ref('dim_product') }}  p  on p.product_key  = f.product_key
join {{ ref('dim_customer') }} c  on c.customer_key = f.customer_key
join {{ ref('dim_store') }}    s  on s.store_key    = f.store_key
join {{ ref('dim_cashier') }}  ca on ca.cashier_key = f.cashier_key
