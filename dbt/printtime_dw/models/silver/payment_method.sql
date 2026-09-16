-- =============================================================================
-- silver.payment_method
-- Source:  bronze.ref_payment_method
-- Grain:   one row per payment method (business key: silver_payment_method_id)
-- Purpose: clean payment-method lookup (cash, card, check, ...); feeds
--          gold.dim_payment_method.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.payment_method)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_payment_method_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_payment_method') }}
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
            partition by payment_method_id
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
        -- Code/type keep source case; name trimmed + internal spaces collapsed.
        cast(payment_method_id as bigint)                                                     as silver_payment_method_id,
        cast(nullif(trim(method_code), '') as string)                                    as silver_method_code,
        cast(nullif(regexp_replace(trim(method_name), '\\s+', ' '), '') as string)   as silver_method_name,
        cast(nullif(trim(method_type), '') as string)                                    as silver_method_type,
        cast(is_card_flag as boolean)                                                         as silver_is_card_flag,
        cast(is_active_flag as boolean)                                                       as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='payment_method_id') }}

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
                cast(silver_payment_method_id as string),
                coalesce(silver_method_code, ''),
                coalesce(silver_method_name, ''),
                coalesce(silver_method_type, ''),
                coalesce(cast(silver_is_card_flag as string), ''),
                coalesce(cast(silver_is_active_flag as string), '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_payment_method_id = f.silver_payment_method_id
where existing.silver_payment_method_id is null                -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
