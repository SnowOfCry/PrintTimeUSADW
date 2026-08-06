-- =============================================================================
-- gold.dim_payment_method
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per payment-method VERSION (current version: is_current = true).
-- Source:  silver.payment_method
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_payment_method)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §3
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- How this works (ADR-015):
--   * Match on the DURABLE source id (source_record_id = silver_payment_method_id),
--     never on the mutable method_code — a code change must version the row,
--     not orphan its history.
--   * record_hash (SHA-256 of tracked attributes) detects change within a version.
--   * APPEND-only: a changed method gets a NEW version row (row_version + 1);
--     the prior row is left intact and is closed by the post-hook below.
--     (Merge would overwrite in place = Type 1, destroying history.)
--   * Surrogate keys are dbt-managed integers (decision #7): existing versions keep
--     their key; new version rows get max(key) + a running count.
--   * The -1 "Not Provided" member is a literal row, seeded on the first build only.
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='fail',
    indexes=[
        {'columns': ['method_code', 'is_current']},
        {'columns': ['valid_from', 'valid_to']},
    ],
    post_hook=[
        "
        update {{ this }} d
        set    is_current           = false,
               valid_to             = nv.valid_from,
               etl_updated_timestamp = current_timestamp
        from   {{ this }} nv
        where  nv.source_record_id = d.source_record_id
          and  nv.row_version      = d.row_version + 1
          and  d.is_current
          and  d.payment_method_key <> -1
        "
    ]
) }}

-- 1) Read silver and shape the tracked business attributes.
with staged as (
    select
        silver_payment_method_id::varchar(100)              as source_record_id,
        silver_method_code::varchar(20)                     as method_code,
        silver_method_name::varchar(50)                     as method_name,
        silver_method_type::varchar(30)                     as method_type,
        silver_is_active_flag::boolean                      as is_active,
        silver_is_deleted_flag::boolean                     as is_deleted,
        silver_source_system::varchar(50)                   as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        silver_source_updated_at_timestamp                  as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        encode(digest(concat_ws('|',
            coalesce(silver_method_code, ''),
            coalesce(silver_method_name, ''),
            coalesce(silver_method_type, ''),
            coalesce(silver_is_active_flag::text, ''),
            coalesce(silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                      as record_hash
    from {{ ref('payment_method') }}
),

-- 2) Keep only rows that need a NEW version: a new entity, or a changed hash
--    vs. that entity's current version. Unchanged entities emit nothing.
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
    where c.source_record_id is null                      -- brand-new method
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) Assign the dbt-managed surrogate key: every emitted row is a NEW version,
--    so each gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(payment_method_key), 0) from {{ this }} where payment_method_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as payment_method_key,
        (current_row_version + 1)::integer              as row_version,
        c.*
    from changed c
),

final as (
    select
        payment_method_key,
        method_code,
        method_name,
        method_type,
        is_active,
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
-- -1 "Not Provided" member (ADR-011) — first build only; it is never re-emitted,
-- so the append never duplicates it.
union all
select
    -1::integer, 'Not Provided'::varchar(20), 'Not Provided'::varchar(50),
    'Not Provided'::varchar(30), false,
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    date '1900-01-01', null::date, true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
