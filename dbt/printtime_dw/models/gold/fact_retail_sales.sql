-- =============================================================================
-- gold.fact_retail_sales
-- Type:    transaction fact (no SCD2 — facts are measurements, never versioned).
-- Grain:   one row per INVOICE LINE.
-- Source:  silver.invoice_line; header: silver.invoice
-- Keys:    dim_date, dim_cashier, dim_product, dim_customer, dim_store, dim_invoice
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.fact_retail_sales)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §9
--          ADR-007 (per-grain fact loads), ADR-009 (no source business keys),
--          ADR-011 (-1 Not Provided fallback), gold decision #3 (change detection)
--
-- How this loads (gold decision #3 — incremental reload-by-invoice):
--   * The reload unit is the INVOICE, not the line (ADR-009). An invoice whose
--     header or any line changed is deleted from the fact and reinserted whole,
--     so edits, added lines and voids are all handled without needing a line id.
--   * Changed invoices are found via silver_updated_at_timestamp > the last
--     successful gold batch for this table in audit.etl_batch_control.
--     delete+insert on invoice_number implements the reload atomically.
--   * Dimension keys are resolved by EFFECTIVE DATE (audit HIGH-3): the SCD2 version
--     whose [valid_from, valid_to) window contains silver_invoice_date, on the
--     durable source_record_id (decision #1) — so a sale carries the dimension
--     attributes that were true WHEN IT HAPPENED, not the entity's current ones. An
--     unresolved lookup falls back to the -1 Not Provided member (ADR-011).
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='invoice_number',
    on_schema_change='fail'
) }}

-- 1) Invoice lines joined to their header. On incremental runs, keep only the
--    invoices touched since the last successful gold batch (decision #3).
with source_lines as (
    select
        l.silver_invoice_line_id,
        l.silver_invoice_id,
        l.silver_product_id,
        l.silver_order_qty,
        l.silver_unit_price_amount,
        l.silver_unit_cost_amount,
        l.silver_line_total_amount,
        l.silver_source_system,
        i.silver_invoice_number,
        i.silver_invoice_date,
        i.silver_customer_id,
        i.silver_store_id,
        i.silver_employee_id
    from {{ ref('invoice_line') }} l
    join {{ ref('invoice') }} i
      on i.silver_invoice_id = l.silver_invoice_id
    {% if is_incremental() %}
    where i.silver_invoice_number in (
        -- reload the whole invoice when the header OR any of its lines changed
        select i2.silver_invoice_number
        from {{ ref('invoice') }} i2
        left join {{ ref('invoice_line') }} l2 on l2.silver_invoice_id = i2.silver_invoice_id
        where i2.silver_updated_at_timestamp > (
                  select coalesce(max(batch_end_timestamp), '1900-01-01'::timestamp)
                  from audit.etl_batch_control
                  where target_table = 'gold.fact_retail_sales'
                    and batch_status = 'succeeded'
              )
           or l2.silver_updated_at_timestamp > (
                  select coalesce(max(batch_end_timestamp), '1900-01-01'::timestamp)
                  from audit.etl_batch_control
                  where target_table = 'gold.fact_retail_sales'
                    and batch_status = 'succeeded'
              )
    )
    {% endif %}
),

-- 2) Resolve dimension surrogate keys against the CURRENT version; unmatched -> -1.
keyed as (
    select
        coalesce(dd.date_key,     -1)::integer      as date_key,
        coalesce(dcash.cashier_key, -1)::integer    as cashier_key,
        coalesce(dp.product_key,  -1)::integer      as product_key,
        coalesce(dc.customer_key, -1)::integer      as customer_key,
        coalesce(ds.store_key,    -1)::integer      as store_key,
        coalesce(di.invoice_key,  -1)::integer      as invoice_key,
        s.silver_invoice_number::varchar(30)        as invoice_number,   -- degenerate dim
        s.silver_order_qty::integer                 as sales_qty,
        s.silver_unit_price_amount::numeric(12,2)   as unit_price,
        s.silver_unit_cost_amount::numeric(12,2)    as unit_cost,
        s.silver_line_total_amount::numeric(12,2)   as sales_amount,
        -- derived measures (mapping §9)
        (s.silver_order_qty * s.silver_unit_cost_amount)::numeric(12,2)  as sales_cost,
        (s.silver_line_total_amount
            - (s.silver_order_qty * s.silver_unit_cost_amount))::numeric(12,2) as gross_profit,
        s.silver_source_system::varchar(50)         as source_system,
        s.silver_invoice_line_id::varchar(100)      as source_record_id
    from source_lines s
    left join {{ ref('dim_date') }}     dd    on dd.date              = s.silver_invoice_date
    -- SCD2 keys resolved by EFFECTIVE DATE: the version in effect on the invoice date.
    left join {{ ref('dim_cashier') }}  dcash on dcash.source_record_id = s.silver_employee_id::varchar
                and s.silver_invoice_date >= dcash.valid_from and (s.silver_invoice_date < dcash.valid_to or dcash.valid_to is null)
    left join {{ ref('dim_product') }}  dp    on dp.source_record_id  = s.silver_product_id::varchar
                and s.silver_invoice_date >= dp.valid_from    and (s.silver_invoice_date < dp.valid_to    or dp.valid_to    is null)
    left join {{ ref('dim_customer') }} dc    on dc.source_record_id  = s.silver_customer_id::varchar
                and s.silver_invoice_date >= dc.valid_from    and (s.silver_invoice_date < dc.valid_to    or dc.valid_to    is null)
    left join {{ ref('dim_store') }}    ds    on ds.source_record_id  = s.silver_store_id::varchar
                and s.silver_invoice_date >= ds.valid_from    and (s.silver_invoice_date < ds.valid_to    or ds.valid_to    is null)
    left join {{ ref('dim_invoice') }}  di    on di.source_record_id  = s.silver_invoice_id::varchar
                and s.silver_invoice_date >= di.valid_from    and (s.silver_invoice_date < di.valid_to    or di.valid_to    is null)
),

-- 3) dbt-managed surrogate key (decision #7). Facts carry no durable key that
--    anything references, but the PK must stay unique across incremental loads,
--    so continue from the current maximum.
keyed_with_pk as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(sales_line_key), 0) from {{ this }})
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                  as sales_line_key,
        k.*
    from keyed k
)

select
    sales_line_key,
    date_key,
    cashier_key,
    product_key,
    customer_key,
    store_key,
    invoice_key,
    invoice_number,
    sales_qty,
    unit_price,
    unit_cost,
    sales_amount,
    sales_cost,
    gross_profit,
    source_system,
    source_record_id,
    '{{ gold_batch_id() }}'::varchar(50) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
    current_timestamp::timestamp    as etl_load_timestamp,
    current_timestamp::timestamp    as etl_updated_timestamp,
    true                            as is_complete,
    false                           as is_validated,
    false                           as dq_issue_flag,
    null::varchar(500)              as dq_issue_description
from keyed_with_pk
