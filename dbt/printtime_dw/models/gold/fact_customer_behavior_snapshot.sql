-- =============================================================================
-- gold.fact_customer_behavior_snapshot
-- Type:    PERIODIC SNAPSHOT fact — append-only; prior snapshots are immutable.
-- Grain:   one row per CUSTOMER per SNAPSHOT DATE.
-- Source:  silver.customer + aggregates over silver.invoice / silver.payment
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.fact_customer_behavior_snapshot)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §11
--          ADR-007 (periodic snapshot), ADR-011 (-1 fallback),
--          gold decision #4 (monthly, month-end cadence)
--
-- Cadence (decision #4): MONTHLY at month-end (~10k rows/month, ~120k/year).
--   The snapshot date defaults to the most recently COMPLETED month-end — you
--   never snapshot a month still in progress. Override for backfills with:
--     dbt run --select fact_customer_behavior_snapshot --vars '{snapshot_date: 2025-11-30}'
--
-- Append-only semantics: this model NEVER rewrites a prior snapshot. The
--   incremental filter drops the whole build if that snapshot_date_key already
--   exists, so re-running on the same day is a no-op rather than a duplicate.
--   Measures are computed AS OF the snapshot date (nothing after it is counted),
--   which is what makes past snapshots reproducible.
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='fail'
) }}

{% set snapshot_date = var('snapshot_date', none) %}

-- 1) The snapshot date: explicit var, else the last completed month-end.
with snapshot_param as (
    select
        {% if snapshot_date %}
        date '{{ snapshot_date }}'                                   as snapshot_date
        {% else %}
        (date_trunc('month', current_date) - interval '1 day')::date as snapshot_date
        {% endif %}
),

-- 2) Per-customer invoice aggregates, AS OF the snapshot date.
invoice_agg as (
    select
        i.silver_customer_id,
        count(distinct i.silver_invoice_id)::integer                          as lifetime_order_count,
        sum(i.silver_total_amount)::numeric(14,2)                             as lifetime_sales_amount,
        count(*) FILTER (
            where i.silver_invoice_date > sp.snapshot_date - interval '30 days'
        )::integer                                                            as orders_last_30_days,
        count(*) FILTER (where i.silver_balance_due_amount > 0)::integer      as open_invoice_count,
        coalesce(sum(i.silver_balance_due_amount)
                 FILTER (where i.silver_balance_due_amount > 0), 0)::numeric(14,2)
                                                                              as open_invoice_total,
        max(i.silver_invoice_date)                                            as last_order_date
    from {{ ref('invoice') }} i
    cross join snapshot_param sp
    where i.silver_invoice_date <= sp.snapshot_date        -- as-of: ignore the future
    group by i.silver_customer_id
),

-- 3) Average days from invoice to full payment, over paid invoices only.
payment_speed as (
    select
        i.silver_customer_id,
        avg(lp.last_payment_date - i.silver_invoice_date)::numeric(8,2)       as avg_days_to_full_payment
    from {{ ref('invoice') }} i
    cross join snapshot_param sp
    join (
        select silver_invoice_id, max(silver_payment_date) as last_payment_date
        from {{ ref('payment') }}
        group by silver_invoice_id
    ) lp on lp.silver_invoice_id = i.silver_invoice_id
    where i.silver_invoice_status = 'paid'
      and i.silver_invoice_date  <= sp.snapshot_date
      and lp.last_payment_date   <= sp.snapshot_date
    group by i.silver_customer_id
),

-- 4) One row per customer, with the dimension keys resolved (unmatched -> -1).
final as (
    select
        coalesce(dd_snap.date_key, -1)::integer                               as snapshot_date_key,
        coalesce(dc.customer_key,  -1)::integer                               as customer_key,
        coalesce(dd_last.date_key, -1)::integer                               as last_order_date_key,
        coalesce(ia.lifetime_order_count, 0)::integer                         as lifetime_order_count,
        coalesce(ia.lifetime_sales_amount, 0)::numeric(14,2)                  as lifetime_sales_amount,
        coalesce(ia.orders_last_30_days, 0)::integer                          as orders_last_30_days,
        ps.avg_days_to_full_payment::numeric(8,2)                             as avg_days_to_full_payment,
        coalesce(ia.open_invoice_count, 0)::integer                           as open_invoice_count,
        coalesce(ia.open_invoice_total, 0)::numeric(14,2)                     as open_invoice_total,
        c.silver_is_active_flag::boolean                                      as is_active_customer,
        c.silver_customer_status::varchar(20)                                 as customer_status,
        c.silver_source_system::varchar(50)                                   as source_system,
        c.silver_customer_id::varchar(100)                                    as source_record_id
    from {{ ref('customer') }} c
    cross join snapshot_param sp
    left join invoice_agg    ia      on ia.silver_customer_id = c.silver_customer_id
    left join payment_speed  ps      on ps.silver_customer_id = c.silver_customer_id
    left join {{ ref('dim_customer') }} dc
           on dc.source_record_id = c.silver_customer_id::varchar and dc.is_current
    left join {{ ref('dim_date') }} dd_snap on dd_snap.date = sp.snapshot_date
    left join {{ ref('dim_date') }} dd_last on dd_last.date = ia.last_order_date
    {% if is_incremental() %}
    -- append-only: skip entirely if this snapshot date was already taken
    where not exists (
        select 1 from {{ this }} t
        where t.snapshot_date_key = coalesce(dd_snap.date_key, -1)
    )
    {% endif %}
),

-- 5) dbt-managed surrogate key (decision #7), continuing from the current max.
keyed as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(snapshot_key), 0) from {{ this }})
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id::bigint)
        )::integer                                      as snapshot_key,
        f.*
    from final f
)

select
    snapshot_key,
    snapshot_date_key,
    customer_key,
    last_order_date_key,
    lifetime_order_count,
    lifetime_sales_amount,
    orders_last_30_days,
    avg_days_to_full_payment,
    open_invoice_count,
    open_invoice_total,
    is_active_customer,
    customer_status,
    source_system,
    source_record_id,
    null::varchar(50)               as etl_batch_id,
    current_timestamp::timestamp    as etl_load_timestamp,
    current_timestamp::timestamp    as etl_updated_timestamp,
    true                            as is_complete,
    false                           as is_validated,
    false                           as dq_issue_flag,
    null::varchar(500)              as dq_issue_description
from keyed
