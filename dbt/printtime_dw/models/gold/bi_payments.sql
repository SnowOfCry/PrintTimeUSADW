-- =============================================================================
-- gold.bi_payments  — BI serving view (ADR-017)
-- Grain:  one row per payment (same as fact_payments).
-- Purpose: report-ready payments/collections, pre-joined to its dimensions.
-- Reads:  gold only (ADR-001).
--
-- REFUND CONVENTION (backlog #5 — encoded here so no tool re-derives it):
--   Refunds are stored as NEGATIVE payment_amount and carry parent_payment_key.
--   SUM(payment_amount) therefore NETS refunds automatically — do not filter or
--   negate them. To report gross vs refunds separately, split on payment_kind
--   (or is_refund), NOT on the sign.
-- Powers: net collections by method/type, refund analysis, cash-flow by month.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    -- ── when ──────────────────────────────────────────────────────────────
    d.date                          as payment_date,
    d.calendar_year                 as payment_year,
    d.calendar_quarter              as payment_quarter,
    d.calendar_year_quarter         as payment_year_quarter,
    d.calendar_month_name           as payment_month_name,
    d.calendar_year_month           as payment_year_month,

    -- ── who / where / how ─────────────────────────────────────────────────
    c.customer_name                 as customer,
    c.customer_city_state           as customer_city_state,
    c.customer_state                as customer_state,
    s.store_name                    as store,
    s.store_region                  as store_region,
    pm.method_name                  as payment_method,
    pm.method_type                  as payment_method_type,
    pt.type_name                    as payment_type,

    -- ── refund handling ───────────────────────────────────────────────────
    (f.parent_payment_key is not null)                                as is_refund,
    case when f.parent_payment_key is not null then 'Refund'
         else 'Payment' end                                           as payment_kind,
    f.payment_sequence_num          as payment_sequence,

    -- ── measures (refunds already negative) ───────────────────────────────
    f.payment_amount                as payment_amount,
    f.tax_amount                    as tax_amount,
    f.fee_amount                    as fee_amount,
    f.net_amount                    as net_amount

from {{ ref('fact_payments') }} f
join {{ ref('dim_date') }}           d  on d.date_key           = f.date_key
join {{ ref('dim_customer') }}       c  on c.customer_key       = f.customer_key
join {{ ref('dim_store') }}          s  on s.store_key          = f.store_key
join {{ ref('dim_payment_method') }} pm on pm.payment_method_key = f.payment_method_key
join {{ ref('dim_payment_type') }}   pt on pt.payment_type_key   = f.payment_type_key
