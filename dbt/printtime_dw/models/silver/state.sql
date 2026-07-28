-- =============================================================================
-- silver.state
-- Source: bronze.ref_state
-- Grain:  one row per state (business key: silver_state_code)
-- Purpose: clean state lookup (CA, AZ, TX); standardizes state for
--          gold.dim_customer and gold.dim_store.
-- Spec:   sql/silver/002_create_silver_tables.sql (silver.state)
--         ADR-005 (cleaning standards), ADR-006 (dedup to one current row/key)
--         docs/load_strategy/silver_incremental_merge_strategy.md (dedup order)
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_state_code',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_state') }}
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
            partition by state_code
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
        upper(trim(state_code))::varchar(2)        as silver_state_code,
        nullif(trim(state_name), '')::varchar(50)  as silver_state_name,

        {{ silver_lineage_and_metadata(source_record_id='state_code') }}

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
                silver_state_code,
                coalesce(silver_state_name, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.* 
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_state_code = f.silver_state_code
where existing.silver_state_code is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}

