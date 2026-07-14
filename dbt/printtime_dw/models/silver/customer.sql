{{ config(
    materialized='incremental',
    unique_key='silver_customer_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as(
    select * from {{ source('bronze', 'oltp_customer')}}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

deduped as(
    select *,
        row_number() over(
            partition by customer_id
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc      
        ) as rn
    from source
),
cleaned as(
    select 
        customer_id::bigint as silver_customer_id,
        nullif(trim(customer_account_no),'')::varchar(30)  as silver_customer_account_no,
        nullif(regexp_replace(trim(business_name), '\s+', ' ', 'g'), '')::varchar(255)  as silver_business_name,
        initcap(nullif(regexp_replace(trim(first_name), '\s+', ' ', 'g'), ''))::varchar(100) as silver_first_name,
        initcap(nullif(regexp_replace(trim(last_name), '\s+', ' ', 'g'), ''))::varchar(100) as silver_last_name,
        case
            when nullif(regexp_replace(trim(business_name), '\s+', ' ', 'g'), '') is not null
            then nullif(regexp_replace(trim(business_name), '\s+', ' ', 'g'), '')
            else initcap(
             nullif(regexp_replace(
                 trim(concat_ws(' ', first_name, last_name)),
             '\s+', ' ', 'g'), '')
         )
        end::varchar(255) as silver_customer_name,
        nullif(trim(lower(email)),'')::varchar(255) as silver_email,
        nullif(regexp_replace(phone, '[^0-9]', '', 'g'), '')::varchar(50) as silver_phone_number,
        case lower(trim(customer_status))
            when 'active'   then 'active'
            when 'inactive' then 'inactive'
        else null                      
        end::varchar(20) as silver_customer_status,
        (lower(trim(customer_status)) = 'active')::boolean as silver_is_active_flag,
        default_tax_rate_id::bigint as silver_default_tax_rate_id,
        home_store_id::bigint as silver_home_store_id,
        first_order_date::date as silver_first_order_date, 

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        customer_id::text                           as silver_source_record_id,
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
final as (
    select *,
        md5(concat_ws('|',
            silver_customer_id::text,
            coalesce(silver_customer_account_no, ''),
            coalesce(silver_business_name, ''),
            coalesce(silver_first_name, ''),
            coalesce(silver_last_name, ''),
            coalesce(silver_customer_name, ''),
            coalesce(silver_email, ''),
            coalesce(silver_phone_number, ''),
            coalesce(silver_customer_status, ''),
            coalesce(silver_is_active_flag::text, ''),
            coalesce(silver_default_tax_rate_id::text, ''),
            coalesce(silver_home_store_id::text, ''),
            coalesce(silver_first_order_date::text, '')
        ))::text as silver_row_hash
    from cleaned
)

select f.* 
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_customer_id = f.silver_customer_id
where existing.silver_customer_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}