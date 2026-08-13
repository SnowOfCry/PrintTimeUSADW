-- =============================================================================
-- silver.econ_indicator
-- Source: bronze.econ_indicator (FRED API)
-- Grain:  one row per (series_id, observation_date)
-- Purpose: clean macroeconomic series (CPI, PPI) feeding the real-terms revenue
--          and input-cost analyses in gold.
-- Spec:   ADR-005 (cleaning standards), ADR-006 (dedup to one row/key),
--         ADR-020 (external FRED source),
--         docs/load_strategy/silver_incremental_merge_strategy.md (dedup order)
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key=['silver_series_id', 'silver_observation_date'],
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'econ_indicator') }}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

-- Collapse bronze's append-only history to the latest row per (series, date).
-- FRED revises values, so the newest observation for a key wins (project-standard
-- freshness order).
deduped as (
    select *,
        row_number() over (
            partition by series_id, observation_date
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc
        ) as rn
    from source
),

cleaned as (

    select
        -- ── business columns (cleaned + cast to spec types) ─────────────────
        upper(trim(series_id))::varchar(50)        as silver_series_id,
        observation_date::date                     as silver_observation_date,
        indicator_value::numeric(18,6)             as silver_indicator_value,
        nullif(trim(units), '')::varchar(50)       as silver_units,

        {{ silver_lineage_and_metadata(source_record_id="series_id || '-' || observation_date::text") }}

    from deduped
    where rn = 1

),

final as (
    select
        *,
        md5(
            concat_ws('|',
                silver_series_id,
                silver_observation_date::text,
                coalesce(silver_indicator_value::text, ''),
                coalesce(silver_units, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on  existing.silver_series_id       = f.silver_series_id
    and existing.silver_observation_date = f.silver_observation_date
where existing.silver_series_id is null
   or existing.silver_row_hash is distinct from f.silver_row_hash
{% endif %}
