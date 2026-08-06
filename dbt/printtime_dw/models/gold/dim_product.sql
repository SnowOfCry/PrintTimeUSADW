-- =============================================================================
-- gold.dim_product
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per product VERSION (current version: is_current = true).
-- Source:  silver.product; lookups: silver.product_category, silver.department
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_product)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §4
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * First dim built from JOINS — category and department attributes are
--     denormalized onto the product row (Kimball flattening), so a category or
--     department rename also versions the affected products. That is intended:
--     the dimension records what the product looked like at that time.
--   * local_made_indicator is a derived label ('Local' / 'Not Local'), not a flag.
--   * Price/markup changes are exactly why this dim is Type 2 — margin analysis
--     must be point-in-time correct (ADR-007).
-- =============================================================================
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='fail',
    indexes=[
        {'columns': ['sku_number', 'is_current']},
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
          and  d.product_key <> -1
        "
    ]
) }}

-- 1) Read silver and flatten the category/department lookups onto the product.
with staged as (
    select
        p.silver_product_id::varchar(100)                       as source_record_id,
        p.silver_product_sku::varchar(50)                       as sku_number,
        p.silver_product_description::varchar(200)              as product_description,
        p.silver_brand_name::varchar(100)                       as brand_description,
        c.silver_category_description::varchar(100)             as category_description,
        d.silver_department_code::varchar(20)                   as department_number,
        d.silver_department_description::varchar(100)           as department_description,
        p.silver_markup_pct::numeric(8,4)                       as markup,
        p.silver_standard_price_amount::numeric(12,2)           as standard_price,
        -- derived label, per the Silver-to-Gold mapping
        (case when p.silver_is_local_made_flag then 'Local' else 'Not Local' end)::varchar(20)
                                                                as local_made_indicator,
        p.silver_is_deleted_flag::boolean                       as is_deleted,
        p.silver_source_system::varchar(50)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        p.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        encode(digest(concat_ws('|',
            coalesce(p.silver_product_sku, ''),
            coalesce(p.silver_product_description, ''),
            coalesce(p.silver_brand_name, ''),
            coalesce(c.silver_category_description, ''),
            coalesce(d.silver_department_code, ''),
            coalesce(d.silver_department_description, ''),
            coalesce(p.silver_markup_pct::text, ''),
            coalesce(p.silver_standard_price_amount::text, ''),
            coalesce(p.silver_is_local_made_flag::text, ''),
            coalesce(p.silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                          as record_hash
    from {{ ref('product') }} p
    left join {{ ref('product_category') }} c
           on c.silver_category_id = p.silver_category_id
    left join {{ ref('department') }} d
           on d.silver_department_id = p.silver_department_id
),

-- 2) Emit only rows needing a NEW version: new product, or changed hash vs. the
--    entity's current version. Unchanged products emit nothing.
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
    where c.source_record_id is null                      -- brand-new product
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) dbt-managed surrogate key (decision #7): each emitted row is a new version,
--    so it gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(product_key), 0) from {{ this }} where product_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as product_key,
        (current_row_version + 1)::integer              as row_version,
        c.*
    from changed c
),

final as (
    select
        product_key,
        sku_number,
        product_description,
        brand_description,
        category_description,
        department_number,
        department_description,
        markup,
        standard_price,
        local_made_indicator,
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
    -1::integer, 'Not Provided'::varchar(50), 'Not Provided'::varchar(200),
    'Not Provided'::varchar(100), 'Not Provided'::varchar(100),
    'Not Provided'::varchar(20), 'Not Provided'::varchar(100),
    null::numeric(8,4), null::numeric(12,2), 'Not Provided'::varchar(20),
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    date '1900-01-01', null::date, true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
