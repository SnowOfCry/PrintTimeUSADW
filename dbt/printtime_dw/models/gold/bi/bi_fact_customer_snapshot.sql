-- =============================================================================
-- gold.bi_fact_customer_snapshot — CUSTOMER BEHAVIOR snapshot fact for BI (ADR-017)
-- Grain: one row per customer per month-end snapshot. Foreign keys + the fact's
-- own measures + two deterministic row-level derivations (days_since_last_order,
-- is_at_risk). Audit/DQ plumbing hidden.
--
-- SEMI-ADDITIVE: never sum a measure across snapshot dates — always slice to one
-- snapshot (measures are point-in-time balances/counts, valid as of that date).
--
-- The two date joins exist only to compute the day arithmetic; no dimension
-- attributes are pulled onto the fact. Both roles keep their surrogate keys
-- (snapshot_date_key, last_order_date_key) for Power BI relationships — the
-- second date role uses vw_last_order_date or an inactive relationship (ADR-010).
--
-- ⚠️ BI-LAYER DEFINITION (ADR-017, no prior spec): is_at_risk = active customer,
--    0 orders in the last 30 days, and >{{ 90 }} days since last order. A proposed
--    default, OPEN for the managers to adjust — one edit here, inherited by every
--    dashboard.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

{% set at_risk_days = 90 %}

select
    -- surrogate key
    f.snapshot_key,

    -- foreign keys → bi_dim_* (two date roles)
    f.snapshot_date_key,
    f.last_order_date_key,
    f.customer_key,

    -- measures (semi-additive — slice to one snapshot date)
    f.lifetime_order_count,
    f.lifetime_sales_amount,
    f.orders_last_30_days,
    f.avg_days_to_full_payment,
    f.open_invoice_count,
    f.open_invoice_total,
    f.is_active_customer,
    f.customer_status,

    -- deterministic row-level derivations
    (sd.date - ld.date)                                         as days_since_last_order,
    case
        when f.is_active_customer
         and f.orders_last_30_days = 0
         and (sd.date - ld.date) > {{ at_risk_days }}
        then true else false
    end                                                         as is_at_risk
from {{ ref('fact_customer_behavior_snapshot') }} f
join {{ ref('dim_date') }} sd on sd.date_key = f.snapshot_date_key
join {{ ref('dim_date') }} ld on ld.date_key = f.last_order_date_key
