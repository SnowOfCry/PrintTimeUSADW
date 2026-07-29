-- =============================================================================
-- gold.bi_fact_payments — PAYMENTS fact for BI (ADR-017)
-- Grain: one row per payment. Foreign keys + degenerate payment_sequence_num +
-- measures. Audit/DQ plumbing hidden.
--
-- REFUND CONVENTION (backlog #5, encoded once so no tool re-derives it):
--   Refunds are stored NEGATIVE and carry parent_payment_key. SUM(payment_amount)
--   nets them automatically. Split gross vs refunds on payment_kind / is_refund,
--   NEVER on the sign. parent_payment_key is kept for drill-through to the
--   original payment.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    -- surrogate key
    payment_key,

    -- foreign keys → bi_dim_*
    date_key,
    customer_key,
    store_key,
    payment_method_key,
    payment_type_key,
    cashier_key,
    invoice_key,

    -- self-reference to the original payment (for refund drill-through)
    parent_payment_key,

    -- degenerate dimension
    payment_sequence_num,

    -- refund helpers (row-level, deterministic)
    (parent_payment_key is not null)                            as is_refund,
    case when parent_payment_key is not null then 'Refund'
         else 'Payment' end                                     as payment_kind,

    -- measures (refunds already negative)
    payment_amount,
    tax_amount,
    fee_amount,
    net_amount
from {{ ref('fact_payments') }}
