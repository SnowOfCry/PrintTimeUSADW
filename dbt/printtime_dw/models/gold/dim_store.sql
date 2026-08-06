-- =============================================================================
-- gold.dim_store
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per store VERSION (current version: is_current = true).
-- Source:  silver.store; lookup: silver.state
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_store)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §5
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * store_id (VARCHAR) is the human-readable store CODE, not the numeric id;
--     the durable numeric id lives in source_record_id and is what SCD2 matches
--     on (decision #1), so a code change versions the row instead of orphaning it.
--   * store_state resolves the 2-letter code to the full state name via
--     silver.state, falling back to the raw code if no match (mapping §5).
--   * Region/type/name changes are why this dim is Type 2 — trend continuity
--     needs the store's attributes as they were at the time (ADR-007).
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='fail',
    indexes=[
        {'columns': ['store_id', 'is_current']},
        {'columns': ['valid_from', 'valid_to']},
    ],
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
          and  d.store_key <> -1
        "
    ]
) }}

-- 1) Read silver and resolve the state-name lookup.
with staged as (
    select
        s.silver_store_id::varchar(100)                         as source_record_id,
        s.silver_store_code::varchar(30)                        as store_id,
        s.silver_store_name::varchar(100)                       as store_name,
        s.silver_city::varchar(100)                             as store_city,
        -- full state name, else fall back to the raw code (mapping §5)
        coalesce(st.silver_state_name, s.silver_state_code)::varchar(50)
                                                                as store_state,
        s.silver_region::varchar(50)                            as store_region,
        s.silver_store_type::varchar(50)                        as store_type,
        s.silver_open_date::date                                as open_date,
        s.silver_is_deleted_flag::boolean                       as is_deleted,
        s.silver_source_system::varchar(50)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        s.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        encode(digest(concat_ws('|',
            coalesce(s.silver_store_code, ''),
            coalesce(s.silver_store_name, ''),
            coalesce(s.silver_city, ''),
            coalesce(coalesce(st.silver_state_name, s.silver_state_code), ''),
            coalesce(s.silver_region, ''),
            coalesce(s.silver_store_type, ''),
            coalesce(s.silver_open_date::text, ''),
            coalesce(s.silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                          as record_hash
    from {{ ref('store') }} s
    left join {{ ref('state') }} st
           on st.silver_state_code = s.silver_state_code
),

-- 2) Emit only rows needing a NEW version: new store, or changed hash vs. the
--    entity's current version. Unchanged stores emit nothing.
changed as (
    select
        s.*
        {% if is_incremental() %}
        , coalesce(c.row_version, 0) as current_row_version
        {% else %}
        , 0::integer    as current_row_version
        {% endif %}
    from staged s
    {% if is_incremental() %}
    left join {{ this }} c
           on c.source_record_id = s.source_record_id
          and c.is_current
    where c.source_record_id is null                      -- brand-new store
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) dbt-managed surrogate key (decision #7): each emitted row is a new version,
--    so it gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(store_key), 0) from {{ this }} where store_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as store_key,
        (current_row_version + 1)::integer              as row_version,
        c.*
    from changed c
),

final as (
    select
        store_key,
        store_id,
        store_name,
        store_city,
        store_state,
        store_region,
        store_type,
        open_date,
        record_hash,
        source_system,
        source_record_id,
        '{{ gold_batch_id() }}'::varchar(50) as etl_batch_id,   -- MED-10: real batch id (joins etl_batch_control.batch_id)
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
    -1::integer, 'Not Provided'::varchar(30), 'Not Provided'::varchar(100),
    'Not Provided'::varchar(100), 'Not Provided'::varchar(50),
    'Not Provided'::varchar(50), 'Not Provided'::varchar(50), null::date,
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    date '1900-01-01', null::date, true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
