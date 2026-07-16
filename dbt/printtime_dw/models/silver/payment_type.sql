-- =============================================================================
-- silver.payment_type
-- Source:  bronze.ref_payment_type
-- Grain:   one row per payment type (business key: silver_payment_type_id)
-- Purpose: clean payment-type lookup (deposit, balance, full, refund, ...);
--          feeds gold.dim_payment_type.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.payment_type)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_payment_type_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_payment_type') }}
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
            partition by payment_type_id
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
        -- Code keeps source case; name/description trimmed + spaces collapsed.
        payment_type_id::bigint                                                          as silver_payment_type_id,
        nullif(trim(type_code), '')::varchar(20)                                         as silver_type_code,
        nullif(regexp_replace(trim(type_name),   '\s+', ' ', 'g'), '')::varchar(50)      as silver_type_name,
        nullif(regexp_replace(trim(description), '\s+', ' ', 'g'), '')::varchar(200)     as silver_type_description,
        affects_balance_flag::boolean                                                    as silver_affects_balance_flag,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        payment_type_id::text                      as silver_source_record_id,
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
                silver_payment_type_id::text,
                coalesce(silver_type_code, ''),
                coalesce(silver_type_name, ''),
                coalesce(silver_type_description, ''),
                coalesce(silver_affects_balance_flag::text, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_payment_type_id = f.silver_payment_type_id
where existing.silver_payment_type_id is null                  -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
