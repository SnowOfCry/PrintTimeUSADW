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
        cast(invoice_line_id as bigint)                                                          as silver_invoice_line_id,
        cast(invoice_id as bigint)                                                               as silver_invoice_id,
        cast(line_number as smallint)                                                            as silver_line_number,
        cast(product_id as bigint)                                                               as silver_product_id,
        cast(variant_id as bigint)                                                               as silver_variant_id,
        cast(nullif(regexp_replace(trim(line_description), '\\s+', ' '), '') as string) as silver_line_description,
        cast(nullif(regexp_replace(trim(color),            '\\s+', ' '), '') as string)  as silver_color,
        cast(order_qty as int)                                                               as silver_order_qty,
        cast(unit_price_amount as decimal(18,2))                                                 as silver_unit_price_amount,
        cast(unit_cost_amount as decimal(18,2))                                                  as silver_unit_cost_amount,
        cast(discount_amount as decimal(18,2))                                                   as silver_discount_amount,
        cast(line_total_amount as decimal(18,2))                                                 as silver_line_total_amount,

        {{ silver_lineage_and_metadata(source_record_id='invoice_line_id') }}

    from deduped
    where rn = 1

),

final as (
    select
        *,
        -- ── change-detection hash over the STANDARDIZED business columns only ──
        -- (metadata is excluded so lineage/timestamps never look like a change;
        --  coalesce guards against concat_ws silently dropping NULLs)
        cast(md5(
            concat_ws('|',
                cast(silver_invoice_line_id as string),
                coalesce(cast(silver_invoice_id as string), ''),
                coalesce(cast(silver_line_number as string), ''),
                coalesce(cast(silver_product_id as string), ''),
                coalesce(cast(silver_variant_id as string), ''),
                coalesce(silver_line_description, ''),
                coalesce(silver_color, ''),
                coalesce(cast(silver_order_qty as string), ''),
                coalesce(cast(silver_unit_price_amount as string), ''),
                coalesce(cast(silver_unit_cost_amount as string), ''),
                coalesce(cast(silver_discount_amount as string), ''),
                coalesce(cast(silver_line_total_amount as string), '')
            )
        ) as string) as silver_row_hash
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
