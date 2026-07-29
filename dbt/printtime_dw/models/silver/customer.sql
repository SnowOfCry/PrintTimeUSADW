-- =============================================================================
-- silver.customer
-- Source:  bronze.oltp_customer
-- Grain:   one row per customer, current state
--          (business key: silver_customer_id)
-- Purpose: clean current state of each customer; feeds gold.dim_customer and
--          gold.fact_customer_behavior_snapshot.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.customer)
--          ADR-005 (cleaning, status vocabulary, derived flags), ADR-006 (merge)
--          docs/load_strategy/silver_incremental_merge_strategy.md (dedup order)
--          docs/source_to_dw_mapping/Bronze_to_Silver_mapping.md §silver.customer
--          ADR-013 (PII classification)
-- Notes:   - customer_status uses the closed lower-case vocabulary (ADR-005 #4):
--            active, inactive — unmapped values become NULL.
--          - two derived columns (ADR-005 #5):
--            silver_customer_name = business name (case PRESERVED) when present,
--              else the Title-Cased person name — the person-vs-business split.
--            silver_is_active_flag = lower(trim(customer_status)) = 'active';
--              derived from status because the source has no is_active column
--              (unlike product/employee/store, which carry one directly).
--          - silver_email and silver_phone_number are classified PII (ADR-013 §1).
--            They stop at silver by design: gold.dim_customer carries neither, so
--            BI never sees raw contact data (ADR-013 §2, data minimization).
-- =============================================================================
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

        {{ silver_lineage_and_metadata(source_record_id='customer_id') }}

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