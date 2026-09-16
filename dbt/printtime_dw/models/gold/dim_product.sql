-- =============================================================================
-- gold.dim_product
-- Type:    SCD Type 2 dimension (versioned history) â€” the ADR-015 pattern.
-- Grain:   one row per product VERSION (current version: is_current = true).
-- Source:  silver.product; lookups: silver.product_category, silver.department
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_product)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md Â§4
--          ADR-007 (Type 2), ADR-015 (dbt SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * First dim built from JOINS â€” category and department attributes are
--     denormalized onto the product row (Kimball flattening), so a category or
--     department rename also versions the affected products. That is intended:
--     the dimension records what the product looked like at that time.
--   * local_made_indicator is a derived label ('Local' / 'Not Local'), not a flag.
--   * Price/markup changes are exactly why this dim is Type 2 â€” margin analysis
--     must be point-in-time correct (ADR-007).
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
          and  d.product_key <> -1
        "
    ]
) }}

-- 1) Read silver and flatten the category/department lookups onto the product.
with staged as (
    select
        cast(p.silver_product_id as string)                       as source_record_id,
        cast(p.silver_product_sku as string)                       as sku_number,
        cast(p.silver_product_description as string)              as product_description,
        cast(p.silver_brand_name as string)                       as brand_description,
        cast(c.silver_category_description as string)             as category_description,
        cast(d.silver_department_code as string)                   as department_number,
        cast(d.silver_department_description as string)           as department_description,
        cast(p.silver_markup_pct as decimal(8,4))                       as markup,
        cast(p.silver_standard_price_amount as decimal(12,2))           as standard_price,
        -- derived label, per the Silver-to-Gold mapping
        cast((case when p.silver_is_local_made_flag then 'Local' else 'Not Local' end) as string)
                                                                as local_made_indicator,
        cast(p.silver_is_deleted_flag as boolean)                       as is_deleted,
        cast(p.silver_source_system as string)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        p.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: a change here = a new version.
        cast(encode(digest(concat_ws('|',
            coalesce(p.silver_product_sku, ''),
            coalesce(p.silver_product_description, ''),
            coalesce(p.silver_brand_name, ''),
            coalesce(c.silver_category_description, ''),
            coalesce(d.silver_department_code, ''),
            coalesce(d.silver_department_description, ''),
            coalesce(cast(p.silver_markup_pct as string), ''),
            coalesce(cast(p.silver_standard_price_amount as string), ''),
            coalesce(cast(p.silver_is_local_made_flag as string), ''),
            coalesce(cast(p.silver_is_deleted_flag as string), '')
        ), 'sha256'), 'hex') as string)                          as record_hash
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
        , cast(0 as int)    as current_row_version
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
        cast((
            {% if is_incremental() %}
            (select coalesce(max(product_key), 0) from {{ this }} where product_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        ) as int)                                      as product_key,
        cast((current_row_version + 1) as int)              as row_version,
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
    cast('Not Provided' as string), cast('Not Provided' as string),
    cast('Not Provided' as string), cast('Not Provided' as string),
    cast(null as decimal(8,4)), cast(null as decimal(12,2)), cast('Not Provided' as string),
    cast(null as string), cast('system' as string), cast('-1' as string), cast(null as string),
    cast(current_timestamp() as timestamp), cast(current_timestamp() as timestamp),
    date '1900-01-01', cast(null as date), true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, cast(null as string), false, cast(null as timestamp)
{% endif %}
