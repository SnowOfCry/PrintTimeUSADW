-- =============================================================================
-- silver.customer_status_history
-- Source:  bronze.oltp_customer_status_history
-- Grain:   one row per status transition (business key: silver_status_history_id)
-- Purpose: clean customer status transitions. HISTORY-TRACKED — one row per
--          transition, never collapsed — the status timeline is the business
--          record; supports customer-status history for
--          gold.fact_customer_behavior_snapshot.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.customer_status_history)
--          ADR-006 §"Deliberate exception" (history-tracked), ADR-005 (vocab).
-- Notes:   - Insert-only audit table: source has no created/updated timestamps,
--            only changed_at (event time). The dedup order and
--            silver_source_created/updated all use changed_at.
--          - old_status/new_status use the closed lower-case customer-status
--            vocabulary (ADR-005 #4): active, inactive.
--          - renames: changed_by -> changed_by_employee_id, reason -> change_reason.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_status_history_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_customer_status_history') }}
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
        customer_id::bigint                        as silver_customer_id,
        -- Closed lower-case customer-status vocabulary (ADR-005 #4); unmapped -> NULL.
        case lower(trim(old_status))
            when 'active'   then 'active'
            when 'inactive' then 'inactive'
            else null
        end::varchar(20)                           as silver_old_status,
        case lower(trim(new_status))
            when 'active'   then 'active'
            when 'inactive' then 'inactive'
            else null
        end::varchar(20)                           as silver_new_status,
        changed_at_source_timestamp::timestamp     as silver_changed_at_timestamp,
        changed_by::bigint                         as silver_changed_by_employee_id,
        nullif(regexp_replace(trim(reason), '\s+', ' ', 'g'), '')::varchar(200) as silver_change_reason,

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
        md5(
            concat_ws('|',
                silver_status_history_id::text,
                coalesce(silver_customer_id::text, ''),
                coalesce(silver_old_status, ''),
                coalesce(silver_new_status, ''),
                coalesce(silver_changed_at_timestamp::text, ''),
                coalesce(silver_changed_by_employee_id::text, ''),
                coalesce(silver_change_reason, '')
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
