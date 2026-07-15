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
        employee_id::bigint                                                                as silver_employee_id,
        nullif(trim(employee_code), '')::varchar(30)                                       as silver_employee_code,
        initcap(nullif(regexp_replace(trim(first_name), '\s+', ' ', 'g'), ''))::varchar(100)  as silver_first_name,
        initcap(nullif(regexp_replace(trim(last_name),  '\s+', ' ', 'g'), ''))::varchar(100)  as silver_last_name,
        -- Derived: source full_name is empty, so build it from first + last.
        initcap(nullif(regexp_replace(
            trim(concat_ws(' ', first_name, last_name)), '\s+', ' ', 'g'), ''))::varchar(200)  as silver_full_name,
        nullif(trim(lower(email)), '')::varchar(255)                                       as silver_email,
        nullif(regexp_replace(phone, '[^0-9]', '', 'g'), '')::varchar(50)                  as silver_phone_number,
        nullif(trim(role), '')::varchar(30)                                                as silver_role,
        store_id::bigint                                                                   as silver_store_id,
        hire_date::date                                                                    as silver_hire_date,
        is_active_flag::boolean                                                            as silver_is_active_flag,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        employee_id::text                          as silver_source_record_id,
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
                silver_employee_id::text,
                coalesce(silver_employee_code, ''),
                coalesce(silver_first_name, ''),
                coalesce(silver_last_name, ''),
                coalesce(silver_full_name, ''),
                coalesce(silver_email, ''),
                coalesce(silver_phone_number, ''),
                coalesce(silver_role, ''),
                coalesce(silver_store_id::text, ''),
                coalesce(silver_hire_date::text, ''),
                coalesce(silver_is_active_flag::text, '')
            )
        )::text as silver_row_hash
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
