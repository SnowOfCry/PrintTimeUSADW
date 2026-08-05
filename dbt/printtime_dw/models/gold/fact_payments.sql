-- =============================================================================
-- gold.fact_payments
-- Type:    transaction fact (no SCD2 — facts are measurements, never versioned).
-- Grain:   one row per PAYMENT.
-- Source:  silver.payment
-- Keys:    dim_invoice, dim_customer, dim_payment_method, dim_date,
--          dim_payment_type, dim_cashier, dim_store, + self-ref parent_payment_key
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.fact_payments)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §10
--          ADR-007 (per-grain fact loads), ADR-009 (no source business keys),
--          ADR-011 (-1 fallback), gold decision #3 (change detection)
--
-- REFUND SIGN CONVENTION (backlog #5 — read before building BI measures):
--   Refunds are stored as NEGATIVE amounts and carry parent_payment_key pointing
--   at the payment they reverse (1,354 refunds, summing to -19,275,453.64).
--   SUM(payment_amount) therefore NETS refunds automatically. BI must not filter
--   refunds out or negate them again — either would double-count the reversal.
--
-- parent_payment_key resolution (the "second pass", ADR-009):
--   The refund chain exists in silver as parent_payment_id, but the fact stores
--   no payment_id. ADR-009 verified that (invoice_id, payment_sequence) is unique
--   across all 57,409 payments, so the parent is re-found deterministically:
--     refund -> its parent's (invoice_id, payment_sequence) -> that row's payment_key.
--   This is done as a self-join INSIDE the model (one pass, no post-hook UPDATE),
--   which keeps the resolution atomic with the load and idempotent on re-runs.
--
-- Load (gold decision #3): incremental delete+insert keyed on source_record_id;
--   changed payments are those with silver_updated_at_timestamp > the last
--   successful gold batch for this table in audit.etl_batch_control.
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='source_record_id',
    on_schema_change='fail'
) }}

-- 1) Read silver payments. On incremental runs, keep only payments touched since
--    the last successful gold batch (decision #3).
with source_payments as (
    select *
    from {{ ref('payment') }} p
    {% if is_incremental() %}
    where p.silver_updated_at_timestamp > (
        select coalesce(max(batch_end_timestamp), '1900-01-01'::timestamp)
        from audit.etl_batch_control
        where target_table = 'gold.fact_payments'
          and batch_status = 'succeeded'
    )
    {% endif %}
),

-- 2) Resolve dimension surrogate keys against the CURRENT version; unmatched -> -1.
keyed as (
    select
        coalesce(di.invoice_key,        -1)::integer     as invoice_key,
        coalesce(dc.customer_key,       -1)::integer     as customer_key,
        coalesce(dpm.payment_method_key,-1)::integer     as payment_method_key,
        coalesce(dd.date_key,           -1)::integer     as date_key,
        coalesce(dpt.payment_type_key,  -1)::integer     as payment_type_key,
        coalesce(dcash.cashier_key,     -1)::integer     as cashier_key,
        coalesce(ds.store_key,          -1)::integer     as store_key,
        p.silver_payment_sequence_num::smallint          as payment_sequence_num,
        p.silver_payment_amount::numeric(12,2)           as payment_amount,
        p.silver_tax_amount::numeric(12,2)               as tax_amount,
        p.silver_fee_amount::numeric(12,2)               as fee_amount,
        p.silver_net_amount::numeric(12,2)               as net_amount,
        p.silver_source_system::varchar(50)              as source_system,
        p.silver_payment_id::varchar(100)                as source_record_id,
        -- carried only to resolve the refund chain below; not stored (ADR-009)
        p.silver_parent_payment_id                       as parent_payment_id
    from source_payments p
    -- SCD2 keys resolved by EFFECTIVE DATE (audit HIGH-3): the version in effect on
    -- the payment date — [valid_from, valid_to) — not the entity's current version.
    left join {{ ref('dim_invoice') }}        di    on di.source_record_id    = p.silver_invoice_id::varchar
                and p.silver_payment_date >= di.valid_from  and (p.silver_payment_date < di.valid_to  or di.valid_to  is null)
    left join {{ ref('dim_customer') }}       dc    on dc.source_record_id    = p.silver_customer_id::varchar
                and p.silver_payment_date >= dc.valid_from  and (p.silver_payment_date < dc.valid_to  or dc.valid_to  is null)
    left join {{ ref('dim_payment_method') }} dpm   on dpm.source_record_id   = p.silver_payment_method_id::varchar
                and p.silver_payment_date >= dpm.valid_from and (p.silver_payment_date < dpm.valid_to or dpm.valid_to is null)
    left join {{ ref('dim_date') }}           dd    on dd.date                = p.silver_payment_date
    -- dim_payment_type is Type 1 and keyed on type_code, so hop through silver
    -- to translate the payment's type id into that code.
    left join {{ ref('payment_type') }}       spt   on spt.silver_payment_type_id = p.silver_payment_type_id
    left join {{ ref('dim_payment_type') }}   dpt   on dpt.type_code          = spt.silver_type_code
    left join {{ ref('dim_cashier') }}        dcash on dcash.source_record_id = p.silver_employee_id::varchar
                and p.silver_payment_date >= dcash.valid_from and (p.silver_payment_date < dcash.valid_to or dcash.valid_to is null)
    left join {{ ref('dim_store') }}          ds    on ds.source_record_id    = p.silver_store_id::varchar
                and p.silver_payment_date >= ds.valid_from  and (p.silver_payment_date < ds.valid_to  or ds.valid_to  is null)
),

-- 3) dbt-managed surrogate key (decision #7), continuing from the current max.
keyed_with_pk as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(payment_key), 0) from {{ this }})
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id::bigint)
        )::integer                                       as payment_key,
        k.*
    from keyed k
),

-- 4) Resolve parent_payment_key: a refund points at its parent's silver id; the
--    parent's payment_key is found via that same id in this load's key assignment.
with_parent as (
    select
        c.payment_key,
        c.invoice_key,
        c.customer_key,
        c.payment_method_key,
        c.date_key,
        c.payment_type_key,
        c.cashier_key,
        c.store_key,
        parent.payment_key                               as parent_payment_key,
        c.payment_sequence_num,
        c.payment_amount,
        c.tax_amount,
        c.fee_amount,
        c.net_amount,
        c.source_system,
        c.source_record_id
    from keyed_with_pk c
    left join keyed_with_pk parent
           on parent.source_record_id = c.parent_payment_id::varchar
)

select
    payment_key,
    invoice_key,
    customer_key,
    payment_method_key,
    date_key,
    payment_type_key,
    cashier_key,
    store_key,
    parent_payment_key,
    payment_sequence_num,
    payment_amount,
    tax_amount,
    fee_amount,
    net_amount,
    source_system,
    source_record_id,
    '{{ gold_batch_id() }}'::varchar(50) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
    current_timestamp::timestamp    as etl_load_timestamp,
    current_timestamp::timestamp    as etl_updated_timestamp,
    true                            as is_complete,
    false                           as is_validated,
    false                           as dq_issue_flag,
    null::varchar(500)              as dq_issue_description
from with_parent
