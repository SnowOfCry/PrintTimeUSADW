-- =============================================================================
-- silver.tax_rate
-- Source:  bronze.ref_tax_rate
-- Grain:   one row per tax rate (business key: silver_tax_rate_id)
-- Purpose: clean tax-rate lookup; supports tax reconciliation for
--          gold.dim_invoice and gold.fact_payments.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.tax_rate)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Note:    source columns are renamed to the silver spec: description ->
--          tax_description, effective_from/to -> effective_from/to_date.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_tax_rate_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_tax_rate') }}
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
            partition by tax_rate_id
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
        -- Code keeps source case; description trimmed + spaces collapsed.
        cast(tax_rate_id as bigint)                                                          as silver_tax_rate_id,
        cast(nullif(trim(tax_code), '') as string)                                      as silver_tax_code,
        cast(nullif(regexp_replace(trim(description), '\\s+', ' '), '') as string) as silver_tax_description,
        cast(rate_pct as decimal(6,4))                                                       as silver_rate_pct,
        cast(effective_from as date)                                                         as silver_effective_from_date,
        cast(effective_to as date)                                                           as silver_effective_to_date,
        cast(is_active_flag as boolean)                                                      as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='tax_rate_id') }}

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
                cast(silver_tax_rate_id as string),
                coalesce(silver_tax_code, ''),
                coalesce(silver_tax_description, ''),
                coalesce(cast(silver_rate_pct as string), ''),
                coalesce(cast(silver_effective_from_date as string), ''),
                coalesce(cast(silver_effective_to_date as string), ''),
                coalesce(cast(silver_is_active_flag as string), '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_tax_rate_id = f.silver_tax_rate_id
where existing.silver_tax_rate_id is null                      -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
