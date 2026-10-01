-- =============================================================================
-- silver.store
-- Source:  bronze.oltp_store
-- Grain:   one row per store/location (business key: silver_store_id)
-- Purpose: clean current version of each store; feeds gold.dim_store and the
--          store labels used in dim_cashier and dim_invoice.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.store)
--          ADR-005 (cleaning + address normalization), ADR-006 (merge)
-- Note:    silver_state_code is upper-cased to match silver.state (the FK it
--          resolves against).
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_store_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_store') }}
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
            partition by store_id
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
        -- Names/address/region: trim + collapse internal spaces. Codes keep
        -- source case; state_code upper-cased; phone reduced to digits only.
        cast(store_id as bigint)                                                                as silver_store_id,
        cast(nullif(trim(store_code), '') as string)                                       as silver_store_code,
        cast(nullif(regexp_replace(trim(store_name),      '\\s+', ' '), '') as string)   as silver_store_name,
        cast(nullif(regexp_replace(trim(street_address),  '\\s+', ' '), '') as string)   as silver_street_address,
        cast(nullif(regexp_replace(trim(city),            '\\s+', ' '), '') as string)   as silver_city,
        cast(nullif(upper(trim(state_code)), '') as string)                                  as silver_state_code,
        cast(nullif(trim(zip_code), '') as string)                                          as silver_zip_code,
        cast(nullif(regexp_replace(phone, '[^0-9]', ''), '') as string)                as silver_phone_number,
        cast(nullif(regexp_replace(trim(region),          '\\s+', ' '), '') as string)    as silver_region,
        cast(nullif(trim(store_type), '') as string)                                        as silver_store_type,
        cast(open_date as date)                                                                 as silver_open_date,
        cast(is_active_flag as boolean)                                                          as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='store_id') }}

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
                cast(silver_store_id as string),
                coalesce(silver_store_code, ''),
                coalesce(silver_store_name, ''),
                coalesce(silver_street_address, ''),
                coalesce(silver_city, ''),
                coalesce(silver_state_code, ''),
                coalesce(silver_zip_code, ''),
                coalesce(silver_phone_number, ''),
                coalesce(silver_region, ''),
                coalesce(silver_store_type, ''),
                coalesce(cast(silver_open_date as string), ''),
                coalesce(cast(silver_is_active_flag as string), '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_store_id = f.silver_store_id
where existing.silver_store_id is null                         -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
