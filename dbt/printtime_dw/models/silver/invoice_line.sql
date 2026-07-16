-- =============================================================================
-- silver.invoice_line
-- Source:  bronze.oltp_invoice_line
-- Grain:   one row per invoice line (business key: silver_invoice_line_id)
-- Purpose: clean current version of each invoice line; the grain source for
--          gold.fact_retail_sales.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.invoice_line)
--          ADR-005 (cleaning standards), ADR-006 (dedup + incremental merge)
-- Note:    variant_id and color are legitimately nullable (not every line has
--          a product variant or a color); they are carried through as-is.
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_invoice_line_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_invoice_line') }}
    {% if is_incremental() %}
        where bronze_batch_id > (select coalesce(max(silver_bronze_batch_id), 0) from {{ this }})
    {% endif %}
),

-- Collapse bronze's append-only history to the latest row per business key.
-- Ordering is the project-standard freshness rule (silver_incremental_merge_strategy):
--   source updated ts → source created ts → bronze load ts → bronze surrogate id.
deduped as (
    select *,
        row_number() over (
            partition by invoice_line_id
            order by updated_at_source_timestamp desc nulls last,
                     created_at_source_timestamp desc nulls last,
                     bronze_loaded_at_timestamp  desc,
                     bronze_record_id            desc
        ) as rn
    from source
),

cleaned as (

    select
        -- ── business columns (cleaned + cast to the DDL types) ──────────────
        -- Description/color: trim + collapse internal spaces, preserve case.
        invoice_line_id::bigint                                                          as silver_invoice_line_id,
        invoice_id::bigint                                                               as silver_invoice_id,
        line_number::smallint                                                            as silver_line_number,
        product_id::bigint                                                               as silver_product_id,
        variant_id::bigint                                                               as silver_variant_id,
        nullif(regexp_replace(trim(line_description), '\s+', ' ', 'g'), '')::varchar(300) as silver_line_description,
        nullif(regexp_replace(trim(color),            '\s+', ' ', 'g'), '')::varchar(40)  as silver_color,
        order_qty::integer                                                               as silver_order_qty,
        unit_price_amount::numeric(18,2)                                                 as silver_unit_price_amount,
        unit_cost_amount::numeric(18,2)                                                  as silver_unit_cost_amount,
        discount_amount::numeric(18,2)                                                   as silver_discount_amount,
        line_total_amount::numeric(18,2)                                                 as silver_line_total_amount,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        invoice_line_id::text                      as silver_source_record_id,
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
    select
        *,
        -- ── change-detection hash over the STANDARDIZED business columns only ──
        -- (metadata is excluded so lineage/timestamps never look like a change;
        --  coalesce guards against concat_ws silently dropping NULLs)
        md5(
            concat_ws('|',
                silver_invoice_line_id::text,
                coalesce(silver_invoice_id::text, ''),
                coalesce(silver_line_number::text, ''),
                coalesce(silver_product_id::text, ''),
                coalesce(silver_variant_id::text, ''),
                coalesce(silver_line_description, ''),
                coalesce(silver_color, ''),
                coalesce(silver_order_qty::text, ''),
                coalesce(silver_unit_price_amount::text, ''),
                coalesce(silver_unit_cost_amount::text, ''),
                coalesce(silver_discount_amount::text, ''),
                coalesce(silver_line_total_amount::text, '')
            )
        )::text as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_invoice_line_id = f.silver_invoice_line_id
where existing.silver_invoice_line_id is null                  -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
