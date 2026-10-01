-- =============================================================================
-- silver.department
-- Source : bronze.oltp_department
-- Grain  : one row per department (business key: silver_department_id)
-- Purpose: clean department lookup (SIGNS, EMB, DTF, PRINT); supplies the
--          department code/name/description that gold.dim_product rolls up to.
-- Spec   : sql/silver/002_create_silver_tables.sql (silver.department)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Load   : incremental merge — one current row per key, updated only on change.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_department_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

-- 1) Pull from bronze. On incremental runs, only read batches we haven't
--    processed yet (watermark = the highest bronze batch already in silver).
with source as (
    select * from {{ source('bronze', 'oltp_department') }}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

-- 2) Bronze is append-only, so a department can appear several times. Keep only
--    the latest version per key using the project-standard freshness order.
deduped as (
    select *,
        row_number() over (
            partition by department_id
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc
        ) as rn
    from source
),

-- 3) Cast to the DDL types and standardize. Codes keep their source case;
--    names/descriptions get trimmed and internal spaces collapsed so equal
--    values become identical strings (stable hash, no phantom changes).
cleaned as (
    select
        -- ── business columns ────────────────────────────────────────────────
        cast(department_id as bigint)                                                     as silver_department_id,
        cast(nullif(trim(department_code), '') as string)                            as silver_department_code,
        cast(nullif(regexp_replace(trim(department_name), '\\s+', ' '), '') as string)  as silver_department_name,
        cast(nullif(regexp_replace(trim(description),     '\\s+', ' '), '') as string)  as silver_department_description,
        cast(is_active_flag as boolean)                                                   as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='department_id') }}

    from deduped
    where rn = 1
),

-- 4) Change-detection hash over the standardized business columns only
--    (never metadata, or every run would look like a change).
final as (
    select *,
        cast(md5(concat_ws('|',
            cast(silver_department_id as string),
            coalesce(silver_department_code, ''),
            coalesce(silver_department_name, ''),
            coalesce(silver_department_description, ''),
            coalesce(cast(silver_is_active_flag as string), '')
        )) as string) as silver_row_hash
    from cleaned
)

-- 5) Hash gate: on incremental runs, emit a row only if its key is new or its
--    hash actually changed — so the merge touches genuinely-changed rows only.
select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_department_id = f.silver_department_id
where existing.silver_department_id is null
   or existing.silver_row_hash is distinct from f.silver_row_hash
{% endif %}
