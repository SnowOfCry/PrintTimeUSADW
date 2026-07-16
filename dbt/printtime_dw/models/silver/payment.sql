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
        payment_id::bigint                         as silver_payment_id,
        invoice_id::bigint                         as silver_invoice_id,
        customer_id::bigint                        as silver_customer_id,
        payment_method_id::bigint                  as silver_payment_method_id,
        payment_type_id::bigint                    as silver_payment_type_id,
        employee_id::bigint                        as silver_employee_id,
        store_id::bigint                           as silver_store_id,
        parent_payment_id::bigint                  as silver_parent_payment_id,
        payment_sequence_num::smallint             as silver_payment_sequence_num,
        -- Closed lower-case status vocabulary (ADR-005 #4); unmapped -> NULL (DQ signal).
        case lower(trim(payment_status))
            when 'pending'  then 'pending'
            when 'cleared'  then 'cleared'
            when 'failed'   then 'failed'
            when 'refunded' then 'refunded'
            when 'void'     then 'void'
            else null
        end::varchar(20)                           as silver_payment_status,
        payment_date::date                         as silver_payment_date,
        gross_amount::numeric(18,2)                as silver_payment_amount,   -- renamed from gross_amount
        tax_amount::numeric(18,2)                  as silver_tax_amount,
        fee_amount::numeric(18,2)                  as silver_fee_amount,
        net_amount::numeric(18,2)                  as silver_net_amount,
        nullif(trim(reference_no), '')::varchar(60) as silver_reference_no,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        payment_id::text                           as silver_source_record_id,
        created_at_source_timestamp::timestamp     as silver_source_created_at_timestamp,
        updated_at_source_timestamp::timestamp     as silver_source_updated_at_timestamp,
        bronze_record_id::bigint                   as silver_bronze_record_id,
        bronze_batch_id::bigint                    as silver_bronze_batch_id,

        -- ── silver's own metadata (stamped as this row is built) ────────────
        {{ var('silver_batch_id', -1) }}::bigint   as silver_batch_id,
        current_timestamp::timestamp               as silver_created_at_timestamp,
        current_timestamp::timestamp               as silver_updated_at_timestamp,
        bronze_is_deleted_flag::boolean            as silver_is_deleted_flag

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
                silver_payment_id::text,
                coalesce(silver_invoice_id::text, ''),
                coalesce(silver_customer_id::text, ''),
                coalesce(silver_payment_method_id::text, ''),
                coalesce(silver_payment_type_id::text, ''),
                coalesce(silver_employee_id::text, ''),
                coalesce(silver_store_id::text, ''),
                coalesce(silver_parent_payment_id::text, ''),
                coalesce(silver_payment_sequence_num::text, ''),
                coalesce(silver_payment_status, ''),
                coalesce(silver_payment_date::text, ''),
                coalesce(silver_payment_amount::text, ''),
                coalesce(silver_tax_amount::text, ''),
                coalesce(silver_fee_amount::text, ''),
                coalesce(silver_net_amount::text, ''),
                coalesce(silver_reference_no, '')
            )
        )::text as silver_row_hash
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
