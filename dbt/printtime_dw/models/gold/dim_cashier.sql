-- =============================================================================
-- gold.dim_cashier
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per cashier VERSION (current version: is_current = true).
-- Source:  silver.employee; lookup: silver.store
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_cashier)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §6
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * is_active is a VARCHAR(3) label ('Yes'/'No') here, not a boolean — the
--     gold DDL and mapping §6 both specify the text form for BI readability.
--   * The employee's store is denormalized onto the row (code + name), so a
--     store reassignment — or a store rename — versions the cashier. That is
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
        update {{ this }} d
        set    is_current            = false,
               valid_to              = nv.valid_from,
               etl_updated_timestamp = current_timestamp
        from   {{ this }} nv
        where  nv.source_record_id = d.source_record_id
          and  nv.row_version      = d.row_version + 1
          and  d.is_current
          and  d.cashier_key <> -1
        "
    ]
) }}

-- 1) Read silver and denormalize the employee's store (code + name).
with staged as (
    select
        e.silver_employee_id::varchar(100)                      as source_record_id,
        e.silver_employee_code::varchar(30)                     as cashier_id,
        e.silver_first_name::varchar(50)                        as cashier_first_name,
        e.silver_last_name::varchar(50)                         as cashier_last_name,
        e.silver_full_name::varchar(100)                        as cashier_full_name,
        -- 'Yes'/'No' text label per the DDL + mapping §6
        (case when e.silver_is_active_flag then 'Yes' else 'No' end)::varchar(3)
                                                                as is_active,
        s.silver_store_code::varchar(30)                        as store_id,
        s.silver_store_name::varchar(100)                       as store_name,
        e.silver_is_deleted_flag::boolean                       as is_deleted,
        e.silver_source_system::varchar(50)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        e.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        encode(digest(concat_ws('|',
            coalesce(e.silver_employee_code, ''),
            coalesce(e.silver_first_name, ''),
            coalesce(e.silver_last_name, ''),
            coalesce(e.silver_full_name, ''),
            coalesce(e.silver_is_active_flag::text, ''),
            coalesce(s.silver_store_code, ''),
            coalesce(s.silver_store_name, ''),
            coalesce(e.silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                          as record_hash
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
        , c.row_version as current_row_version
        {% else %}
        , 0::integer    as current_row_version
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
        (
            {% if is_incremental() %}
            (select coalesce(max(cashier_key), 0) from {{ this }} where cashier_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as cashier_key,
        (current_row_version + 1)::integer              as row_version,
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
        null::varchar(50)               as etl_batch_id,
        current_timestamp::timestamp    as etl_load_timestamp,
        current_timestamp::timestamp    as etl_updated_timestamp,
        -- Effective date (audit HIGH-3): initial version from a low-watermark;
        -- later versions from the source update instant. Never the load date.
        (case when row_version = 1
              then date '1900-01-01'
              else src_updated_at::date
         end)                           as valid_from,
        null::date                      as valid_to,      -- open version
        true                            as is_current,
        row_version,
        true                            as is_complete,
        false                           as is_validated,
        false                           as dq_issue_flag,
        null::varchar(500)              as dq_issue_description,
        is_deleted,
        null::timestamp                 as deleted_timestamp
    from keyed
)

select * from final

{% if not is_incremental() %}
-- -1 "Not Provided" member (ADR-011) — first build only, so the append never
-- duplicates it.
union all
select
    -1::integer, 'Not Provided'::varchar(30), 'Not Provided'::varchar(50),
    'Not Provided'::varchar(50), 'Not Provided'::varchar(100), 'No'::varchar(3),
    'Not Provided'::varchar(30), 'Not Provided'::varchar(100),
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    date '1900-01-01', null::date, true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
