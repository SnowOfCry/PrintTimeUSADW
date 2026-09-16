-- =============================================================================
-- gold.fact_customer_behavior_snapshot
-- Type:    PERIODIC SNAPSHOT fact â€” append-only; prior snapshots are immutable.
-- Grain:   one row per CUSTOMER per SNAPSHOT DATE.
-- Source:  silver.customer + aggregates over silver.invoice / silver.payment
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.fact_customer_behavior_snapshot)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md Â§11
--          ADR-007 (periodic snapshot), ADR-011 (-1 fallback),
--          gold decision #4 (monthly, month-end cadence)
--
-- Cadence (decision #4): MONTHLY at month-end (~10k rows/month, ~120k/year).
--   The snapshot date defaults to the most recently COMPLETED month-end â€” you
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
        cast(last_day(add_months(current_date(), -1)) as date) as snapshot_date
        {% endif %}
),

-- 2) Per-customer invoice aggregates, AS OF the snapshot date.
invoice_agg as (
    select
        i.silver_customer_id,
        cast(count(distinct i.silver_invoice_id) as int)                          as lifetime_order_count,
        cast(sum(i.silver_total_amount) as decimal(14,2))                             as lifetime_sales_amount,
        cast(count(*) FILTER (
            where i.silver_invoice_date > date_sub(sp.snapshot_date, 30)
        ) as int)                                                            as orders_last_30_days,
        cast(count(*) FILTER (where i.silver_balance_due_amount > 0) as int)      as open_invoice_count,
        cast(coalesce(sum(i.silver_balance_due_amount)
                 FILTER (where i.silver_balance_due_amount > 0), 0) as decimal(14,2))
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
        cast(avg(datediff(lp.last_payment_date, i.silver_invoice_date)) as decimal(8,2))       as avg_days_to_full_payment
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
        cast(coalesce(dd_snap.date_key, -1) as int)                               as snapshot_date_key,
        cast(coalesce(dc.customer_key,  -1) as int)                               as customer_key,
        cast(coalesce(dd_last.date_key, -1) as int)                               as last_order_date_key,
        cast(coalesce(ia.lifetime_order_count, 0) as int)                         as lifetime_order_count,
        cast(coalesce(ia.lifetime_sales_amount, 0) as decimal(14,2))                  as lifetime_sales_amount,
        cast(coalesce(ia.orders_last_30_days, 0) as int)                          as orders_last_30_days,
        cast(ps.avg_days_to_full_payment as decimal(8,2))                             as avg_days_to_full_payment,
        cast(coalesce(ia.open_invoice_count, 0) as int)                           as open_invoice_count,
        cast(coalesce(ia.open_invoice_total, 0) as decimal(14,2))                     as open_invoice_total,
        cast(c.silver_is_active_flag as boolean)                                      as is_active_customer,
        cast(c.silver_customer_status as string)                                 as customer_status,
        cast(c.silver_source_system as string)                                   as source_system,
        cast(c.silver_customer_id as string)                                    as source_record_id
    from {{ ref('customer') }} c
    cross join snapshot_param sp
    left join invoice_agg    ia      on ia.silver_customer_id = c.silver_customer_id
    left join payment_speed  ps      on ps.silver_customer_id = c.silver_customer_id
    -- SCD2 key by EFFECTIVE DATE (audit HIGH-3): the customer version in effect on
    -- the snapshot date, so a past snapshot reflects who they were THEN, not now.
    left join {{ ref('dim_customer') }} dc
           on dc.source_record_id = cast(c.silver_customer_id as string)
          and sp.snapshot_date >= dc.valid_from and (sp.snapshot_date < dc.valid_to or dc.valid_to is null)
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
        cast((
            {% if is_incremental() %}
            (select coalesce(max(snapshot_key), 0) from {{ this }})
            {% else %}
            0
            {% endif %}
            + row_number() over (order by cast(source_record_id as bigint))
        ) as int)                                      as snapshot_key,
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
    cast('{{ gold_batch_id() }}' as string) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
    cast(current_timestamp() as timestamp)    as etl_load_timestamp,
    cast(current_timestamp() as timestamp)    as etl_updated_timestamp,
    true                            as is_complete,
    false                           as is_validated,
    false                           as dq_issue_flag,
    cast(null as string)              as dq_issue_description
from keyed
