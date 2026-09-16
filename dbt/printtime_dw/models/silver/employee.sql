-- =============================================================================
-- silver.employee
-- Source:  bronze.oltp_employee
-- Grain:   one row per employee (business key: silver_employee_id)
-- Purpose: clean current version of each employee (cashiers, managers, sales
--          reps); feeds gold.dim_cashier.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.employee)
--          ADR-005 (cleaning + name/email/phone normalization), ADR-006 (merge)
-- Note:    source full_name is empty, so silver_full_name is DERIVED from
--          first + last (Title Case), matching the silver.customer approach.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_employee_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_employee') }}
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
            partition by employee_id
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
        -- Person names: trim, collapse internal spaces, Title Case (ADR-005).
        -- Codes/roles keep source case; email lowercased; phone digits only.
        cast(employee_id as bigint)                                                                as silver_employee_id,
        cast(nullif(trim(employee_code), '') as string)                                       as silver_employee_code,
        cast(initcap(nullif(regexp_replace(trim(first_name), '\\s+', ' '), '')) as string)  as silver_first_name,
        cast(initcap(nullif(regexp_replace(trim(last_name),  '\\s+', ' '), '')) as string)  as silver_last_name,
        -- Derived: source full_name is empty, so build it from first + last.
        cast(initcap(nullif(regexp_replace(
            trim(concat_ws(' ', first_name, last_name)), '\\s+', ' '), '')) as string)  as silver_full_name,
        cast(nullif(trim(lower(email)), '') as string)                                       as silver_email,
        cast(nullif(regexp_replace(phone, '[^0-9]', ''), '') as string)                  as silver_phone_number,
        cast(nullif(trim(role), '') as string)                                                as silver_role,
        cast(store_id as bigint)                                                                   as silver_store_id,
        cast(hire_date as date)                                                                    as silver_hire_date,
        cast(is_active_flag as boolean)                                                            as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='employee_id') }}

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
                cast(silver_employee_id as string),
                coalesce(silver_employee_code, ''),
                coalesce(silver_first_name, ''),
                coalesce(silver_last_name, ''),
                coalesce(silver_full_name, ''),
                coalesce(silver_email, ''),
                coalesce(silver_phone_number, ''),
                coalesce(silver_role, ''),
                coalesce(cast(silver_store_id as string), ''),
                coalesce(cast(silver_hire_date as string), ''),
                coalesce(cast(silver_is_active_flag as string), '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_employee_id = f.silver_employee_id
where existing.silver_employee_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
