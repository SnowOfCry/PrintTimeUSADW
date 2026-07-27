-- =============================================================================
-- gold.dim_payment_type
-- Type:    Type 1 dimension (overwrite-in-place; no SCD2/history by design).
-- Grain:   one row per payment type (natural key: type_code).
-- Source:  silver.payment_type
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_payment_type)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md, ADR-015
-- Keys:    dbt-managed integer surrogate (existing keys preserved from {{ this }},
--          new types get max(key)+running-count). -1 Not Provided member (ADR-011)
--          flows through the same merge as a UNION ALL row.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='payment_type_key',
    incremental_strategy='merge',
    merge_exclude_columns=['etl_load_timestamp'],
    on_schema_change='fail'
) }}

with staged as (           -- read silver, map/clean the business columns
    select
        silver_type_code                                        as type_code,
        nullif(trim(silver_type_name), '')::varchar(50)         as type_name,
        nullif(trim(silver_type_description), '')::varchar(200) as description,
        silver_is_deleted_flag::boolean                         as is_deleted
    from {{ ref('payment_type') }}
),

keyed as (                 -- assign the surrogate key (existing reused, new = max+offset)
    select
        {% if is_incremental() %}
        coalesce(
            e.payment_type_key,                          -- existing type → reuse its key
            (select coalesce(max(payment_type_key), 0)   -- new type → highest key so far …
             from {{ this }} where payment_type_key <> -1)
            + sum(case when e.payment_type_key is null then 1 else 0 end)  -- … + running count of new rows
              over (order by s.type_code)
        )::integer
        {% else %}
        (row_number() over (order by s.type_code))::integer          -- first build → 1,2,3,…
        {% endif %} as payment_type_key,
        s.type_code,
        s.type_name,
        s.description,
        s.is_deleted
    from staged s
    {% if is_incremental() %}
    left join {{ this }} e on e.type_code = s.type_code
    {% endif %}
),

final as (                 -- add the etl timestamps
    select
        payment_type_key,
        type_code,
        type_name,
        description,
        current_timestamp::timestamp as etl_load_timestamp,
        current_timestamp::timestamp as etl_updated_timestamp,
        is_deleted
    from keyed
)

select * from final
union all
-- -1 "Not Provided" member (ADR-011): flows through the same merge; key stays -1.
select
    -1::integer,
    'Not Provided'::varchar(20),
    'Not Provided'::varchar(50),
    'Not Provided'::varchar(200),
    current_timestamp::timestamp,
    current_timestamp::timestamp,
    false
