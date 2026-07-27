-- =============================================================================
-- gold.dim_customer
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per customer VERSION (current version: is_current = true).
-- Source:  silver.customer
-- Lookups: silver.customer_address (primary address), silver.state, gold.dim_date
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_customer)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §7
--          ADR-007 (Type 2), ADR-015 (SCD2 pattern), ADR-011 (-1 member),
--          ADR-014 (customer_county has no source)
--
-- Notes specific to this dim:
--   * Address grain: joined on silver_is_primary_flag, which is exactly one
--     address per customer (verified: 10,000 primary rows / 10,000 customers,
--     0 with multiples), so the join cannot fan out and duplicate customers.
--   * customer_county is hardcoded 'Not Provided' — no county exists anywhere in
--     OLTP/bronze/silver (ADR-014, backlog #3). It is a documented gap, not a
--     data-quality failure, so dq_issue_flag stays false for it.
--   * first_order_date_key resolves against gold.dim_date — the first dim that
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
               valid_to              = current_date,
               etl_updated_timestamp = current_timestamp
        where  d.is_current
          and  d.customer_key <> -1
          and  exists (
                   select 1 from {{ this }} newer
                   where  newer.source_record_id = d.source_record_id
                     and  newer.row_version      > d.row_version
               )
        "
    ]
) }}

-- 1) Read silver, denormalize the primary address + state name, and resolve the
--    first-order date to its dim_date key.
with staged as (
    select
        c.silver_customer_id::varchar(100)                      as source_record_id,
        c.silver_customer_account_no::varchar(30)               as customer_id,
        c.silver_customer_name::varchar(100)                    as customer_name,
        a.silver_street_address_line_1::varchar(200)            as customer_street_address,
        a.silver_city::varchar(100)                             as customer_city,
        -- No county source anywhere (ADR-014 / backlog #3): documented gap.
        'Not Provided'::varchar(100)                            as customer_county,
        coalesce(st.silver_state_name, a.silver_state_code)::varchar(50)
                                                                as customer_state,
        -- "City, State" display attribute (mapping §7)
        nullif(concat_ws(', ',
            a.silver_city,
            coalesce(st.silver_state_name, a.silver_state_code)
        ), '')::varchar(150)                                    as customer_city_state,
        -- Role-playing FK to dim_date; unmatched -> -1 Not Provided (ADR-011)
        coalesce(dd.date_key, -1)::integer                      as first_order_date_key,
        c.silver_is_deleted_flag::boolean                       as is_deleted,
        c.silver_source_system::varchar(50)                     as source_system,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        encode(digest(concat_ws('|',
            coalesce(c.silver_customer_account_no, ''),
            coalesce(c.silver_customer_name, ''),
            coalesce(a.silver_street_address_line_1, ''),
            coalesce(a.silver_city, ''),
            coalesce(coalesce(st.silver_state_name, a.silver_state_code), ''),
            coalesce(dd.date_key::text, ''),
            coalesce(c.silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                          as record_hash
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
        , c.row_version as current_row_version
        {% else %}
        , 0::integer    as current_row_version
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
        (
            {% if is_incremental() %}
            (select coalesce(max(customer_key), 0) from {{ this }} where customer_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as customer_key,
        (current_row_version + 1)::integer              as row_version,
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
        null::varchar(50)               as etl_batch_id,
        current_timestamp::timestamp    as etl_load_timestamp,
        current_timestamp::timestamp    as etl_updated_timestamp,
        current_date::date              as valid_from,
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
    -1::integer, 'Not Provided'::varchar(30), 'Not Provided'::varchar(100),
    'Not Provided'::varchar(200), 'Not Provided'::varchar(100),
    'Not Provided'::varchar(100), 'Not Provided'::varchar(50),
    'Not Provided'::varchar(150), -1::integer,
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    current_date::date, null::date, true, 1,
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
