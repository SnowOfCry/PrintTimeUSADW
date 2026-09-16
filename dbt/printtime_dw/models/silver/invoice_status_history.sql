-- =============================================================================
-- silver.invoice_status_history
-- Source:  bronze.oltp_invoice_status_history
-- Grain:   one row per status transition (business key: silver_status_history_id)
-- Purpose: clean invoice status transitions. HISTORY-TRACKED — one row per
--          transition, never collapsed to "current" — because the status
--          timeline itself is the business record that feeds SCD2 gold.dim_invoice.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.invoice_status_history)
--          ADR-006 §"Deliberate exception" (history-tracked), ADR-005 (vocab).
-- Notes:   - This is an insert-only audit table: the source has no created/updated
--            timestamps, only changed_at (the event time). So the dedup freshness
--            order and silver_source_created/updated both use changed_at.
--          - old_status/new_status use the closed lower-case invoice-status
--            vocabulary (ADR-005 #4): open, partial, paid, void. old_status is
--            legitimately NULL on the first ("invoice created") transition.
--          - renames: changed_by -> changed_by_employee_id, note -> change_note.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_status_history_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_invoice_status_history') }}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

-- Dedup only guards against re-extracts of the SAME transition (each transition
-- has its own status_history_id, so distinct transitions are all kept). Ordering
-- is the history-table freshness rule (ADR-006): event time changed_at, then
-- bronze load time, then bronze surrogate id.
deduped as (
    select *,
        row_number() over (
            partition by status_history_id
            order by changed_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc
        ) as rn
    from source
),

cleaned as (

    select
        -- ── business columns (cleaned + cast to the DDL types) ──────────────
        cast(status_history_id as bigint)                  as silver_status_history_id,
        cast(invoice_id as bigint)                         as silver_invoice_id,
        -- Closed lower-case invoice-status vocabulary (ADR-005 #4); unmapped -> NULL.
        cast(case lower(trim(old_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end as string)                           as silver_old_status,
        cast(case lower(trim(new_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end as string)                           as silver_new_status,
        cast(changed_at_source_timestamp as timestamp)     as silver_changed_at_timestamp,
        cast(changed_by as bigint)                         as silver_changed_by_employee_id,
        cast(nullif(regexp_replace(trim(note), '\\s+', ' '), '') as string) as silver_change_note,

        {{ silver_lineage_and_metadata(source_record_id='status_history_id', source_created_at='changed_at_source_timestamp', source_updated_at='changed_at_source_timestamp') }}

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
                cast(silver_status_history_id as string),
                coalesce(cast(silver_invoice_id as string), ''),
                coalesce(silver_old_status, ''),
                coalesce(silver_new_status, ''),
                coalesce(cast(silver_changed_at_timestamp as string), ''),
                coalesce(cast(silver_changed_by_employee_id as string), ''),
                coalesce(silver_change_note, '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_status_history_id = f.silver_status_history_id
where existing.silver_status_history_id is null                -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
