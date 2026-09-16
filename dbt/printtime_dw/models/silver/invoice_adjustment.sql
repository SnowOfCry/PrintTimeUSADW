-- =============================================================================
-- silver.invoice_adjustment
-- Source:  bronze.oltp_invoice_adjustment
-- Grain:   one row per adjustment (business key: silver_adjustment_id)
-- Purpose: clean current version of each invoice adjustment (credit/debit);
--          supports total reconciliation for gold.dim_invoice and fact_payments.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.invoice_adjustment)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Notes:   - renames: amount -> adjustment_amount, reason -> adjustment_reason,
--            adjusted_by -> adjusted_by_employee_id.
--          - adjustment_type (CREDIT/DEBIT) is NOT one of ADR-005 #4's controlled
--            status vocabularies, so its source case is preserved.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_adjustment_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_invoice_adjustment') }}
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
            partition by adjustment_id
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
        -- Type kept in source case; reason trimmed + internal spaces collapsed.
        cast(adjustment_id as bigint)                                                          as silver_adjustment_id,
        cast(invoice_id as bigint)                                                             as silver_invoice_id,
        cast(nullif(trim(adjustment_type), '') as string)                                 as silver_adjustment_type,
        cast(amount as decimal(18,2))                                                          as silver_adjustment_amount,
        cast(nullif(regexp_replace(trim(reason), '\\s+', ' '), '') as string)        as silver_adjustment_reason,
        cast(adjusted_by as bigint)                                                            as silver_adjusted_by_employee_id,
        cast(adjustment_date as date)                                                          as silver_adjustment_date,

        {{ silver_lineage_and_metadata(source_record_id='adjustment_id') }}

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
                cast(silver_adjustment_id as string),
                coalesce(cast(silver_invoice_id as string), ''),
                coalesce(silver_adjustment_type, ''),
                coalesce(cast(silver_adjustment_amount as string), ''),
                coalesce(silver_adjustment_reason, ''),
                coalesce(cast(silver_adjusted_by_employee_id as string), ''),
                coalesce(cast(silver_adjustment_date as string), '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_adjustment_id = f.silver_adjustment_id
where existing.silver_adjustment_id is null                    -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
