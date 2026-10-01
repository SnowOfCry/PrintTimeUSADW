-- =============================================================================
-- gold.dim_cashier
-- Type:    SCD Type 2 dimension (versioned history) â€” the ADR-015 pattern.
-- Grain:   one row per cashier VERSION (current version: is_current = true).
-- Source:  silver.employee; lookup: silver.store
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_cashier)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md Â§6
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * is_active is a VARCHAR(3) label ('Yes'/'No') here, not a boolean â€” the
--     gold DDL and mapping Â§6 both specify the text form for BI readability.
--   * The employee's store is denormalized onto the row (code + name), so a
--     store reassignment â€” or a store rename â€” versions the cashier. That is
--     the point of Type 2 here (ADR-007: store reassignment needs history).
--   * Name columns narrow from silver varchar(100) to gold varchar(50)/(100);
--     cast explicitly so the contract holds.
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='fail',
    post_hook=[
        "
        merge into {{ this }} d
        using {{ this }} nv
        on     nv.source_record_id = d.source_record_id
          and  nv.row_version      = d.row_version + 1
          and  d.is_current
          and  d.cashier_key <> -1
        when matched then update set
               is_current            = false,
               valid_to              = nv.valid_from,
               etl_updated_timestamp = current_timestamp()
        "
    ]
) }}

-- 1) Read silver and denormalize the employee's store (code + name).
with staged as (
    select
        cast(e.silver_employee_id as string)                      as source_record_id,
        cast(e.silver_employee_code as string)                     as cashier_id,
        cast(e.silver_first_name as string)                        as cashier_first_name,
        cast(e.silver_last_name as string)                         as cashier_last_name,
        cast(e.silver_full_name as string)                        as cashier_full_name,
        -- 'Yes'/'No' text label per the DDL + mapping Â§6
        cast((case when e.silver_is_active_flag then 'Yes' else 'No' end) as string)
                                                                as is_active,
        cast(s.silver_store_code as string)                        as store_id,
        cast(s.silver_store_name as string)                       as store_name,
        cast(e.silver_is_deleted_flag as boolean)                       as is_deleted,
        cast(e.silver_source_system as string)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        e.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        cast(sha2(concat_ws('|',
            coalesce(e.silver_employee_code, ''),
            coalesce(e.silver_first_name, ''),
            coalesce(e.silver_last_name, ''),
            coalesce(e.silver_full_name, ''),
            coalesce(cast(e.silver_is_active_flag as string), ''),
            coalesce(s.silver_store_code, ''),
            coalesce(s.silver_store_name, ''),
            coalesce(cast(e.silver_is_deleted_flag as string), '')
        ), 256) as string)                          as record_hash
    from {{ ref('employee') }} e
    left join {{ ref('store') }} s
           on s.silver_store_id = e.silver_store_id
),

-- 2) Emit only rows needing a NEW version: new cashier, or changed hash vs. the
--    entity's current version. Unchanged cashiers emit nothing.
changed as (
    select
        s.*
        {% if is_incremental() %}
        , coalesce(c.row_version, 0) as current_row_version
        {% else %}
        , cast(0 as int)    as current_row_version
        {% endif %}
    from staged s
    {% if is_incremental() %}
    left join {{ this }} c
           on c.source_record_id = s.source_record_id
          and c.is_current
    where c.source_record_id is null                      -- brand-new cashier
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) dbt-managed surrogate key (decision #7): each emitted row is a new version,
--    so it gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        cast((
            {% if is_incremental() %}
            (select coalesce(max(cashier_key), 0) from {{ this }} where cashier_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        ) as int)                                      as cashier_key,
        cast((current_row_version + 1) as int)              as row_version,
        c.*
    from changed c
),

final as (
    select
        cashier_key,
        cashier_id,
        cashier_first_name,
        cashier_last_name,
        cashier_full_name,
        is_active,
        store_id,
        store_name,
        record_hash,
        source_system,
        source_record_id,
        cast('{{ gold_batch_id() }}' as string) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
        cast(current_timestamp() as timestamp)    as etl_load_timestamp,
        cast(current_timestamp() as timestamp)    as etl_updated_timestamp,
        -- Effective date (audit HIGH-3): initial version from a low-watermark;
        -- later versions from the source update instant. Never the load date.
        (case when row_version = 1
              then date '1900-01-01'
              else cast(src_updated_at as date)
         end)                           as valid_from,
        cast(null as date)                      as valid_to,      -- open version
        true                            as is_current,
        row_version,
        true                            as is_complete,
        false                           as is_validated,
        false                           as dq_issue_flag,
        cast(null as string)              as dq_issue_description,
        is_deleted,
        cast(null as timestamp)                 as deleted_timestamp
    from keyed
)

select * from final

{% if not is_incremental() %}
-- -1 "Not Provided" member (ADR-011) â€” first build only, so the append never
-- duplicates it.
union all
select
    -cast(1 as int), cast('Not Provided' as string), cast('Not Provided' as string),
    cast('Not Provided' as string), cast('Not Provided' as string), cast('No' as string),
    cast('Not Provided' as string), cast('Not Provided' as string),
    cast(null as string), cast('system' as string), cast('-1' as string), cast(null as string),
    cast(current_timestamp() as timestamp), cast(current_timestamp() as timestamp),
    date '1900-01-01', cast(null as date), true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, cast(null as string), false, cast(null as timestamp)
{% endif %}
