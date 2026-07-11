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

with source as (
    select * from {{ source('bronze', 'ref_state') }}
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

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        state_code::text                           as silver_source_record_id,
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
                silver_state_code,
                coalesce(silver_state_name, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select * from final
