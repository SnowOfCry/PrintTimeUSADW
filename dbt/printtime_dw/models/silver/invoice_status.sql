-- =============================================================================
-- silver.invoice_status
-- Source:  bronze.ref_invoice_status
-- Grain:   one row per invoice status (business key: silver_status_code)
-- Purpose: clean invoice-status lookup; standardizes the invoice status values
--          used by gold.dim_invoice.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.invoice_status)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Note:    the business key is the status CODE, lower-cased per ADR-005 #4
--          (controlled vocabularies are closed LOWER-case sets): open, paid,
--          partial, void. silver.invoice's status values must be lower-cased
--          the same way so the gold FK resolves.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_status_code',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_invoice_status') }}
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
            partition by status_code
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
        -- Status code lower-cased (ADR-005 #4 vocabulary); name trimmed + collapsed.
        nullif(lower(trim(status_code)), '')::varchar(20)                            as silver_status_code,
        nullif(regexp_replace(trim(status_name), '\s+', ' ', 'g'), '')::varchar(50)  as silver_status_name,
        is_terminal_flag::boolean                                                    as silver_is_terminal_flag,
        sort_order::smallint                                                         as silver_sort_order,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        status_code::text                          as silver_source_record_id,
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
                coalesce(silver_status_code, ''),
                coalesce(silver_status_name, ''),
                coalesce(silver_is_terminal_flag::text, ''),
                coalesce(silver_sort_order::text, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_status_code = f.silver_status_code
where existing.silver_status_code is null                      -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
