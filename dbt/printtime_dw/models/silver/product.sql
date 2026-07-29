-- =============================================================================
-- silver.product
-- Source:  bronze.oltp_product
-- Grain:   one row per product, current version
--          (business key: silver_product_id)
-- Purpose: clean current version of each product; feeds gold.dim_product and
--          product attributes for gold.fact_retail_sales.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.product)
--          ADR-005 (cleaning standards), ADR-006 (dedup to one current row/key)
--          docs/load_strategy/silver_incremental_merge_strategy.md (dedup order)
--          docs/source_to_dw_mapping/Bronze_to_Silver_mapping.md §silver.product
-- Notes:   - cost column is RENAMED across the hop: bronze unit_cost_amount ->
--            silver_standard_cost_amount (the DDL name). It is the standard cost
--            of the product, not a per-line cost — fact_retail_sales computes
--            sales_cost from the invoice line's own unit cost, not from here.
--          - silver_is_active_flag comes DIRECTLY from the source is_active_flag
--            (already boolean at source, ADR-005 #5) — unlike silver.customer,
--            which must derive its flag from a status string.
--          - department_id and category_id are both carried. Gold resolves
--            department via product.department_id (the single declared path);
--            see the readiness review on the two-path ambiguity.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_product_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as(
    select * from {{ source('bronze', 'oltp_product')}}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

deduped as(
    select *,
        row_number() over(
            partition by product_id
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc      
        ) as rn
    from source
),
cleaned as(
    select 
        product_id::bigint as silver_product_id,
        trim(sku)::varchar(50)  as silver_product_sku,
        trim(product_name)::varchar(255)  as silver_product_name,
        nullif(trim(description),'')::text as silver_product_description,
        department_id::bigint as silver_department_id,
        category_id::bigint as silver_category_id,
        trim(brand)::varchar(100) as silver_brand_name,
        unit_cost_amount::numeric(18,2) as silver_standard_cost_amount,
        markup_pct::numeric(8,4) as silver_markup_pct,
        standard_price_amount::numeric(18,2) as silver_standard_price_amount,
        is_local_made_flag::boolean as silver_is_local_made_flag,
        is_active_flag::boolean as silver_is_active_flag,

        {{ silver_lineage_and_metadata(source_record_id='product_id') }}

    from deduped
    where rn = 1
),
final as(
    select *,
        md5(concat_ws('|',
            silver_product_id::text,
            coalesce(silver_product_sku, ''),
            coalesce(silver_product_name, ''),
            coalesce(silver_product_description, ''),
            coalesce(silver_department_id::text, ''),
            coalesce(silver_category_id::text, ''),
            coalesce(silver_brand_name, ''),
            coalesce(silver_standard_cost_amount::text, ''),
            coalesce(silver_markup_pct::text, ''),
            coalesce(silver_standard_price_amount::text, ''),
            coalesce(silver_is_local_made_flag::text, ''),
            coalesce(silver_is_active_flag::text, '')
        ))::text as silver_row_hash
    from cleaned
)

select f.* 
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_product_id = f.silver_product_id
where existing.silver_product_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}