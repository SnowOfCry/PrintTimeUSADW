-- =============================================================================
-- silver.payment_status
-- Source:  bronze.ref_payment_status
-- Grain:   one row per payment status (business key: silver_status_code)
-- Purpose: clean payment-status lookup; standardizes the payment status values
--          used by gold.fact_payments.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.payment_status)
--          ADR-005 (cleaning + controlled vocabularies), ADR-006 (merge)
-- Note:    the business key is the status CODE, lower-cased per ADR-005 #4
--          (controlled vocabularies are closed LOWER-case sets): pending,
--          cleared, failed, refunded, void. silver.payment's status value must
--          be lower-cased the same way so the gold FK resolves.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_status_code',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'ref_payment_status') }}
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

        {{ silver_lineage_and_metadata(source_record_id='status_code') }}

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
                coalesce(silver_status_name, '')
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
