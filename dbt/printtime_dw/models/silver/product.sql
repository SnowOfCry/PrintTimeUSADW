with source as(
    select * from {{ source('bronze', 'oltp_product')}}
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

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        product_id::text                           as silver_source_record_id,
        created_at_source_timestamp::timestamp     as silver_source_created_at_timestamp,
        updated_at_source_timestamp::timestamp     as silver_source_updated_at_timestamp,
        bronze_record_id::bigint                   as silver_bronze_record_id,
        bronze_batch_id::bigint                    as silver_bronze_batch_id,

        -- ── silver's own metadata (stamped as this row is built) ────────────
        {{ var('silver_batch_id', -1) }}::bigint   as silver_batch_id,
        current_timestamp::timestamp               as silver_created_at_timestamp,
        current_timestamp::timestamp               as silver_updated_at_timestamp,
        bronze_is_deleted_flag::boolean            as silver_is_deleted_flag

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

select * from final