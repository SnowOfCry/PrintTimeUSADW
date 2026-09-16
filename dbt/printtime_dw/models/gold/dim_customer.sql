-- =============================================================================
-- gold.dim_customer
-- Type:    SCD Type 2 dimension (versioned history) â€” the ADR-015 pattern.
-- Grain:   one row per customer VERSION (current version: is_current = true).
-- Source:  silver.customer
-- Lookups: silver.customer_address (primary address), silver.state, gold.dim_date
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_customer)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md Â§7
--          ADR-007 (Type 2), ADR-015 (SCD2 pattern), ADR-011 (-1 member),
--          ADR-014 (customer_county has no source)
--
-- Notes specific to this dim:
--   * Address grain: joined on silver_is_primary_flag, which is exactly one
--     address per customer (verified: 10,000 primary rows / 10,000 customers,
--     0 with multiples), so the join cannot fan out and duplicate customers.
--   * customer_county is hardcoded 'Not Provided' â€” no county exists anywhere in
--     OLTP/bronze/silver (ADR-014, backlog #3). It is a documented gap, not a
--     data-quality failure, so dq_issue_flag stays false for it.
--   * first_order_date_key resolves against gold.dim_date â€” the first dim that
--     references another GOLD model; unmatched dates fall back to the -1 member
--     (ADR-011). Role-played as vw_first_order_date (ADR-010).
--   * Address/status/city-state changes are why this dim is Type 2 (ADR-007).
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
               etl_updated_timestamp = current_timestamp()
        from   {{ this }} nv
        where  nv.source_record_id = d.source_record_id
          and  nv.row_version      = d.row_version + 1
          and  d.is_current
          and  d.customer_key <> -1
"
    ]
) }}

-- 1) Read silver, denormalize the primary address + state name, and resolve the
--    first-order date to its dim_date key.
with staged as (
    select
        cast(c.silver_customer_id as string)                      as source_record_id,
        cast(c.silver_customer_account_no as string)               as customer_id,
        cast(c.silver_customer_name as string)                    as customer_name,
        cast(a.silver_street_address_line_1 as string)            as customer_street_address,
        cast(a.silver_city as string)                             as customer_city,
        -- No county source anywhere (ADR-014 / backlog #3): documented gap.
        cast('Not Provided' as string)                            as customer_county,
        cast(coalesce(st.silver_state_name, a.silver_state_code) as string)
                                                                as customer_state,
        -- "City, State" display attribute (mapping Â§7)
        cast(nullif(concat_ws(', ',
            a.silver_city,
            coalesce(st.silver_state_name, a.silver_state_code)
        ), '') as string)                                    as customer_city_state,
        -- Role-playing FK to dim_date; unmatched -> -1 Not Provided (ADR-011)
        cast(coalesce(dd.date_key, -1) as int)                      as first_order_date_key,
        cast(c.silver_is_deleted_flag as boolean)                       as is_deleted,
        cast(c.silver_source_system as string)                     as source_system,
        -- Effective-dating input (ADR-015 / audit HIGH-3 fix): a NEW version is dated
        -- by the SOURCE update instant, not the load date, so the history reflects
        -- when the change actually happened rather than when the ETL happened to run.
        c.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        cast(encode(digest(concat_ws('|',
            coalesce(c.silver_customer_account_no, ''),
            coalesce(c.silver_customer_name, ''),
            coalesce(a.silver_street_address_line_1, ''),
            coalesce(a.silver_city, ''),
            coalesce(coalesce(st.silver_state_name, a.silver_state_code), ''),
            coalesce(cast(dd.date_key as string), ''),
            coalesce(cast(c.silver_is_deleted_flag as string), '')
        ), 'sha256'), 'hex') as string)                          as record_hash
    from {{ ref('customer') }} c
    -- exactly one primary address per customer (verified), so no fan-out
    left join {{ ref('customer_address') }} a
           on a.silver_customer_id = c.silver_customer_id
          and a.silver_is_primary_flag
    left join {{ ref('state') }} st
           on st.silver_state_code = a.silver_state_code
    left join {{ ref('dim_date') }} dd
           on dd.date = c.silver_first_order_date
),

-- 2) Emit only rows needing a NEW version: new customer, or changed hash vs. the
--    entity's current version. Unchanged customers emit nothing.
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
    where c.source_record_id is null                      -- brand-new customer
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) dbt-managed surrogate key (decision #7): each emitted row is a new version,
--    so it gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        cast((
            {% if is_incremental() %}
            (select coalesce(max(customer_key), 0) from {{ this }} where customer_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        ) as int)                                      as customer_key,
        cast((current_row_version + 1) as int)              as row_version,
        c.*
    from changed c
),

final as (
    select
        customer_key,
        customer_id,
        customer_name,
        customer_street_address,
        customer_city,
        customer_county,
        customer_state,
        customer_city_state,
        first_order_date_key,
        record_hash,
        source_system,
        source_record_id,
        cast('{{ gold_batch_id() }}' as string) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
        cast(current_timestamp() as timestamp)    as etl_load_timestamp,
        cast(current_timestamp() as timestamp)    as etl_updated_timestamp,
        -- Effective date (audit HIGH-3), never the load date. The source carries only
        -- current state (no pre-load history), so the INITIAL version is effective
        -- from a low-watermark â€” it covers every fact that predates the first real
        -- change. A NEW version (a change detected after go-live) is effective from
        -- the source UPDATE instant. Windows are half-open [valid_from, valid_to).
        (case when row_version = 1
              then date '1900-01-01'
              else cast(src_updated_at as date)
         end)                           as valid_from,
        cast(null as date)                      as valid_to,      -- open version (closed by post-hook)
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
    cast('Not Provided' as string), cast('Not Provided' as string),
    cast('Not Provided' as string), cast('Not Provided' as string),
    cast('Not Provided' as string), -cast(1 as int),
    cast(null as string), cast('system' as string), cast('-1' as string), cast(null as string),
    cast(current_timestamp() as timestamp), cast(current_timestamp() as timestamp),
    date '1900-01-01', cast(null as date), true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, cast(null as string), false, cast(null as timestamp)
{% endif %}
