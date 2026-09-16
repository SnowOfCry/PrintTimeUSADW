-- =============================================================================
-- gold.dim_payment_method
-- Type:    SCD Type 2 dimension (versioned history) â€” the ADR-015 pattern.
-- Grain:   one row per payment-method VERSION (current version: is_current = true).
-- Source:  silver.payment_method
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_payment_method)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md Â§3
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- How this works (ADR-015):
--   * Match on the DURABLE source id (source_record_id = silver_payment_method_id),
--     never on the mutable method_code â€” a code change must version the row,
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
    post_hook=[
        "
        update {{ this }} d
        set    is_current           = false,
               valid_to             = nv.valid_from,
               etl_updated_timestamp = current_timestamp()
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
        cast(silver_payment_method_id as string)              as source_record_id,
        cast(silver_method_code as string)                     as method_code,
        cast(silver_method_name as string)                     as method_name,
        cast(silver_method_type as string)                     as method_type,
        cast(silver_is_active_flag as boolean)                      as is_active,
        cast(silver_is_deleted_flag as boolean)                     as is_deleted,
        cast(silver_source_system as string)                   as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        silver_source_updated_at_timestamp                  as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        cast(encode(digest(concat_ws('|',
            coalesce(silver_method_code, ''),
            coalesce(silver_method_name, ''),
            coalesce(silver_method_type, ''),
            coalesce(cast(silver_is_active_flag as string), ''),
            coalesce(cast(silver_is_deleted_flag as string), '')
        ), 'sha256'), 'hex') as string)                      as record_hash
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
        , cast(0 as int)    as current_row_version
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
        cast((
            {% if is_incremental() %}
            (select coalesce(max(payment_method_key), 0) from {{ this }} where payment_method_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        ) as int)                                      as payment_method_key,
        cast((current_row_version + 1) as int)              as row_version,
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
-- -1 "Not Provided" member (ADR-011) â€” first build only; it is never re-emitted,
-- so the append never duplicates it.
union all
select
    -cast(1 as int), cast('Not Provided' as string), cast('Not Provided' as string),
    cast('Not Provided' as string), false,
    cast(null as string), cast('system' as string), cast('-1' as string), cast(null as string),
    cast(current_timestamp() as timestamp), cast(current_timestamp() as timestamp),
    date '1900-01-01', cast(null as date), true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, cast(null as string), false, cast(null as timestamp)
{% endif %}
