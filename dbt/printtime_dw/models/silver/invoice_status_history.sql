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
        status_history_id::bigint                  as silver_status_history_id,
        invoice_id::bigint                         as silver_invoice_id,
        -- Closed lower-case invoice-status vocabulary (ADR-005 #4); unmapped -> NULL.
        case lower(trim(old_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end::varchar(20)                           as silver_old_status,
        case lower(trim(new_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end::varchar(20)                           as silver_new_status,
        changed_at_source_timestamp::timestamp     as silver_changed_at_timestamp,
        changed_by::bigint                         as silver_changed_by_employee_id,
        nullif(regexp_replace(trim(note), '\s+', ' ', 'g'), '')::varchar(200) as silver_change_note,

        -- ── source lineage carried forward from bronze ──────────────────────
        -- Insert-only audit rows: changed_at is the only source lifecycle time,
        -- so it stands in for both source created and source updated.
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        status_history_id::text                    as silver_source_record_id,
        changed_at_source_timestamp::timestamp     as silver_source_created_at_timestamp,
        changed_at_source_timestamp::timestamp     as silver_source_updated_at_timestamp,
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
                silver_status_history_id::text,
                coalesce(silver_invoice_id::text, ''),
                coalesce(silver_old_status, ''),
                coalesce(silver_new_status, ''),
                coalesce(silver_changed_at_timestamp::text, ''),
                coalesce(silver_changed_by_employee_id::text, ''),
                coalesce(silver_change_note, '')
            )
        )::text as silver_row_hash
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
