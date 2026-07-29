-- =============================================================================
-- silver.refund
-- Source:  bronze.oltp_refund
-- Grain:   one row per refund (business key: silver_refund_id)
-- Purpose: clean current version of each refund, chained to its payment;
--          supports refund analysis in gold.fact_payments.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.refund)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Note:    source columns renamed to the silver spec: reason -> refund_reason,
--          refunded_by -> refunded_by_employee_id.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_refund_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_refund') }}
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
            partition by refund_id
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
        -- Reason: trim + collapse internal spaces, preserve case.
        refund_id::bigint                                                             as silver_refund_id,
        payment_id::bigint                                                            as silver_payment_id,
        invoice_id::bigint                                                            as silver_invoice_id,
        refund_amount::numeric(18,2)                                                  as silver_refund_amount,
        refund_date::date                                                             as silver_refund_date,
        nullif(regexp_replace(trim(reason), '\s+', ' ', 'g'), '')::varchar(200)       as silver_refund_reason,
        refunded_by::bigint                                                           as silver_refunded_by_employee_id,

        {{ silver_lineage_and_metadata(source_record_id='refund_id') }}

    from deduped
    where rn = 1

),

final as (
    select
        *,
        -- ── change-detection hash over the STANDARDIZED business columns only ──
        -- (metadata is excluded so lineage/timestamps never look like a change;
        --  coalesce guards against concat_ws silently dropping NULLs)
        md5(
            concat_ws('|',
                silver_refund_id::text,
                coalesce(silver_payment_id::text, ''),
                coalesce(silver_invoice_id::text, ''),
                coalesce(silver_refund_amount::text, ''),
                coalesce(silver_refund_date::text, ''),
                coalesce(silver_refund_reason, ''),
                coalesce(silver_refunded_by_employee_id::text, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_refund_id = f.silver_refund_id
where existing.silver_refund_id is null                        -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
