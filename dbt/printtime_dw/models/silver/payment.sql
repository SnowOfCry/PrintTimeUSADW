-- =============================================================================
-- silver.payment
-- Source:  bronze.oltp_payment
-- Grain:   one row per payment (business key: silver_payment_id)
-- Purpose: clean current version of each payment; grain source for
--          gold.fact_payments (incl. the refund chain via parent_payment_id).
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.payment)
--          ADR-005 (cleaning + payment_status vocabulary), ADR-006 (merge)
-- Notes:   - silver_payment_amount is renamed from source gross_amount.
--          - payment_status is mapped to the closed lower-case vocabulary
--            (ADR-005 #4): pending, cleared, failed, refunded, void.
--          - parent_payment_id is a nullable self-reference (refund -> original)
--            carried through as-is; the refund chain is resolved in gold.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_payment_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_payment') }}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

-- Collapse bronze's append-only history to the latest row per business key.
-- Ordering is the project-standard freshness rule (silver_incremental_merge_strategy):
--   source updated ts → source created ts → bronze load ts → bronze surrogate id.
deduped as (
    select *,
        row_number() over (
            partition by payment_id
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc
        ) as rn
    from source
),

cleaned as (

    select
        -- ── business columns (cleaned + cast to the DDL types) ──────────────
        cast(payment_id as bigint)                         as silver_payment_id,
        cast(invoice_id as bigint)                         as silver_invoice_id,
        cast(customer_id as bigint)                        as silver_customer_id,
        cast(payment_method_id as bigint)                  as silver_payment_method_id,
        cast(payment_type_id as bigint)                    as silver_payment_type_id,
        cast(employee_id as bigint)                        as silver_employee_id,
        cast(store_id as bigint)                           as silver_store_id,
        cast(parent_payment_id as bigint)                  as silver_parent_payment_id,
        cast(payment_sequence_num as smallint)             as silver_payment_sequence_num,
        -- Closed lower-case status vocabulary (ADR-005 #4); unmapped -> NULL (DQ signal).
        cast(case lower(trim(payment_status))
            when 'pending'  then 'pending'
            when 'cleared'  then 'cleared'
            when 'failed'   then 'failed'
            when 'refunded' then 'refunded'
            when 'void'     then 'void'
            else null
        end as string)                           as silver_payment_status,
        cast(payment_date as date)                         as silver_payment_date,
        cast(gross_amount as decimal(18,2))                as silver_payment_amount,   -- renamed from gross_amount
        cast(tax_amount as decimal(18,2))                  as silver_tax_amount,
        cast(fee_amount as decimal(18,2))                  as silver_fee_amount,
        cast(net_amount as decimal(18,2))                  as silver_net_amount,
        cast(nullif(trim(reference_no), '') as string) as silver_reference_no,

        {{ silver_lineage_and_metadata(source_record_id='payment_id') }}

    from deduped
    where rn = 1

),

final as (
    select
        *,
        -- ── change-detection hash over the STANDARDIZED business columns only ──
        -- (metadata is excluded so lineage/timestamps never look like a change;
        --  coalesce guards against concat_ws silently dropping NULLs)
        cast(md5(
            concat_ws('|',
                cast(silver_payment_id as string),
                coalesce(cast(silver_invoice_id as string), ''),
                coalesce(cast(silver_customer_id as string), ''),
                coalesce(cast(silver_payment_method_id as string), ''),
                coalesce(cast(silver_payment_type_id as string), ''),
                coalesce(cast(silver_employee_id as string), ''),
                coalesce(cast(silver_store_id as string), ''),
                coalesce(cast(silver_parent_payment_id as string), ''),
                coalesce(cast(silver_payment_sequence_num as string), ''),
                coalesce(silver_payment_status, ''),
                coalesce(cast(silver_payment_date as string), ''),
                coalesce(cast(silver_payment_amount as string), ''),
                coalesce(cast(silver_tax_amount as string), ''),
                coalesce(cast(silver_fee_amount as string), ''),
                coalesce(cast(silver_net_amount as string), ''),
                coalesce(silver_reference_no, '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_payment_id = f.silver_payment_id
where existing.silver_payment_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
