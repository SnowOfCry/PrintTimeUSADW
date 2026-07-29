-- =============================================================================
-- gold.bi_customer_snapshot  — BI serving view (ADR-017)
-- Grain:  one row per customer per snapshot date (same as the snapshot fact).
-- Purpose: report-ready customer behavior, with the two date roles resolved and
--          derived helpers (days since last order, at-risk flag).
-- Reads:  gold only (ADR-001). Uses the role-playing date joins (ADR-010):
--          snapshot_date_key and last_order_date_key both point at dim_date.
-- Powers: lifetime value, "who's slipping away" (at-risk), open balances.
--
-- ⚠️ BI-LAYER DEFINITION (no prior spec — ADR-017): "at-risk" is defined here as
--    an active customer with NO orders in the last 30 days AND more than 90 days
--    since their last order. This threshold is a proposed default, documented in
--    the gold data dictionary, and explicitly OPEN for the managers to adjust —
--    changing it is a one-line edit here, inherited by every dashboard.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

{% set at_risk_days = 90 %}

select
    -- ── snapshot period ───────────────────────────────────────────────────
    sd.date                         as snapshot_date,
    sd.calendar_year_month          as snapshot_year_month,

    -- ── customer ──────────────────────────────────────────────────────────
    c.customer_name                 as customer,
    c.customer_city_state           as customer_city_state,
    c.customer_state                as customer_state,
    f.customer_status               as customer_status,
    f.is_active_customer            as is_active_customer,

    -- ── recency ───────────────────────────────────────────────────────────
    ld.date                         as last_order_date,
    (sd.date - ld.date)             as days_since_last_order,

    -- ── behavior measures ─────────────────────────────────────────────────
    f.lifetime_order_count          as lifetime_orders,
    f.lifetime_sales_amount         as lifetime_sales,
    f.orders_last_30_days           as orders_last_30_days,
    f.avg_days_to_full_payment      as avg_days_to_full_payment,
    f.open_invoice_count            as open_invoice_count,
    f.open_invoice_total            as open_invoice_total,

    -- ── derived: at-risk (see header; threshold {{ at_risk_days }} days) ───
    case
        when f.is_active_customer
         and f.orders_last_30_days = 0
         and (sd.date - ld.date) > {{ at_risk_days }}
        then true else false
    end                             as is_at_risk

from {{ ref('fact_customer_behavior_snapshot') }} f
join {{ ref('dim_customer') }} c  on c.customer_key = f.customer_key
join {{ ref('dim_date') }}     sd on sd.date_key    = f.snapshot_date_key
join {{ ref('dim_date') }}     ld on ld.date_key    = f.last_order_date_key
