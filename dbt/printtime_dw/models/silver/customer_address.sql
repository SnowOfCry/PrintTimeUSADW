-- =============================================================================
-- silver.customer_address
-- Source:  bronze.oltp_customer_address
-- Grain:   one row per address (business key: silver_address_id)
-- Purpose: clean current version of each customer address; supplies address
--          enrichment to gold.dim_customer.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.customer_address)
--          ADR-005 (cleaning + address_type vocabulary), ADR-006 (merge)
-- Notes:   - address_type uses the closed lower-case vocabulary (ADR-005 #4):
--            billing, shipping.
--          - renames: street_address -> street_address_line_1,
--            street_address2 -> street_address_line_2.
--          - state_code is upper-cased to match silver.state (the FK it resolves).
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_address_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_customer_address') }}
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
            partition by address_id
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
        -- Address lines/city: trim + collapse spaces. state_code upper-cased.
        address_id::bigint                                                               as silver_address_id,
        customer_id::bigint                                                              as silver_customer_id,
        -- Closed lower-case address-type vocabulary (ADR-005 #4); unmapped -> NULL.
        case lower(trim(address_type))
            when 'billing'  then 'billing'
            when 'shipping' then 'shipping'
            else null
        end::varchar(20)                                                                 as silver_address_type,
        nullif(regexp_replace(trim(street_address),  '\s+', ' ', 'g'), '')::varchar(200)  as silver_street_address_line_1,
        nullif(regexp_replace(trim(street_address2), '\s+', ' ', 'g'), '')::varchar(100)  as silver_street_address_line_2,
        nullif(regexp_replace(trim(city),            '\s+', ' ', 'g'), '')::varchar(100)  as silver_city,
        nullif(upper(trim(state_code)), '')::varchar(2)                                  as silver_state_code,
        nullif(trim(zip_code), '')::varchar(10)                                          as silver_zip_code,
        is_primary_flag::boolean                                                         as silver_is_primary_flag,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        address_id::text                           as silver_source_record_id,
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
                silver_address_id::text,
                coalesce(silver_customer_id::text, ''),
                coalesce(silver_address_type, ''),
                coalesce(silver_street_address_line_1, ''),
                coalesce(silver_street_address_line_2, ''),
                coalesce(silver_city, ''),
                coalesce(silver_state_code, ''),
                coalesce(silver_zip_code, ''),
                coalesce(silver_is_primary_flag::text, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_address_id = f.silver_address_id
where existing.silver_address_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
