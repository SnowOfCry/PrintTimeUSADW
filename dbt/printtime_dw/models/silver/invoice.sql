-- =============================================================================
-- silver.invoice
-- Source:  bronze.oltp_invoice
-- Grain:   one row per invoice, current state / latest status
--          (business key: silver_invoice_id)
-- Purpose: clean current state of each invoice; feeds gold.dim_invoice,
--          fact_retail_sales, and fact_payments. Status changes flow via the
--          merge while bronze keeps the full history.
-- Spec:    sql/silver/002_create_silver_tables.sql (silver.invoice)
--          ADR-005 (cleaning, status vocabulary, derived flags), ADR-006 (merge)
-- Notes:   - invoice_status uses the closed lower-case vocabulary (ADR-005 #4):
--            open, partial, paid, void — matches silver.invoice_status for the
--            gold FK join.
--          - two derived flags (ADR-005 #5), computed from the raw amounts:
--            has_balance_due = balance_due_amount > 0
--            paid_in_full    = paid_amount >= total_amount  (excludes VOID,
--            which is closed with a balance <= 0 but was never fully paid).
-- =============================================================================
{{ config(
    materialized='incremental',
    unique_key='silver_invoice_id',
    incremental_strategy='merge',
    merge_exclude_columns=['silver_created_at_timestamp'],
    on_schema_change='fail'
) }}

with source as (
    select * from {{ source('bronze', 'oltp_invoice') }}
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
            partition by invoice_id
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
        cast(invoice_id as bigint)                                                            as silver_invoice_id,
        cast(nullif(trim(invoice_number), '') as string)                                 as silver_invoice_number,
        cast(customer_id as bigint)                                                           as silver_customer_id,
        cast(store_id as bigint)                                                              as silver_store_id,
        cast(employee_id as bigint)                                                           as silver_employee_id,
        cast(billing_address_id as bigint)                                                    as silver_billing_address_id,
        cast(shipping_address_id as bigint)                                                   as silver_shipping_address_id,
        cast(nullif(trim(po_number), '') as string)                                      as silver_po_number,
        cast(invoice_date as date)                                                            as silver_invoice_date,
        cast(invoice_due_date as date)                                                        as silver_invoice_due_date,
        -- Closed lower-case invoice-status vocabulary (ADR-005 #4); unmapped -> NULL.
        cast(case lower(trim(invoice_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end as string)                                                              as silver_invoice_status,
        cast(tax_rate_id as bigint)                                                           as silver_tax_rate_id,
        cast(subtotal_amount as decimal(18,2))                                                as silver_subtotal_amount,
        cast(discount_amount as decimal(18,2))                                                as silver_discount_amount,
        cast(tax_amount as decimal(18,2))                                                     as silver_tax_amount,
        cast(fee_amount as decimal(18,2))                                                     as silver_fee_amount,
        cast(total_amount as decimal(18,2))                                                   as silver_total_amount,
        cast(paid_amount as decimal(18,2))                                                    as silver_paid_amount,
        cast(balance_due_amount as decimal(18,2))                                             as silver_balance_due_amount,
        -- Derived business flags (ADR-005 #5), computed from the raw amounts so
        -- they cannot reference the silver aliases defined in this same SELECT.
        cast((balance_due_amount > 0) as boolean)                                             as silver_has_balance_due_flag,
        cast((paid_amount >= total_amount) as boolean)                                        as silver_paid_in_full_flag,
        cast(nullif(regexp_replace(trim(notes), '\\s+', ' '), '') as string)       as silver_notes,

        {{ silver_lineage_and_metadata(source_record_id='invoice_id') }}

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
                cast(silver_invoice_id as string),
                coalesce(silver_invoice_number, ''),
                coalesce(cast(silver_customer_id as string), ''),
                coalesce(cast(silver_store_id as string), ''),
                coalesce(cast(silver_employee_id as string), ''),
                coalesce(cast(silver_billing_address_id as string), ''),
                coalesce(cast(silver_shipping_address_id as string), ''),
                coalesce(silver_po_number, ''),
                coalesce(cast(silver_invoice_date as string), ''),
                coalesce(cast(silver_invoice_due_date as string), ''),
                coalesce(silver_invoice_status, ''),
                coalesce(cast(silver_tax_rate_id as string), ''),
                coalesce(cast(silver_subtotal_amount as string), ''),
                coalesce(cast(silver_discount_amount as string), ''),
                coalesce(cast(silver_tax_amount as string), ''),
                coalesce(cast(silver_fee_amount as string), ''),
                coalesce(cast(silver_total_amount as string), ''),
                coalesce(cast(silver_paid_amount as string), ''),
                coalesce(cast(silver_balance_due_amount as string), ''),
                coalesce(cast(silver_has_balance_due_flag as string), ''),
                coalesce(cast(silver_paid_in_full_flag as string), ''),
                coalesce(silver_notes, '')
            )
        ) as string) as silver_row_hash
    from cleaned
)

select f.*
from final f
{% if is_incremental() %}
left join {{ this }} existing
    on existing.silver_invoice_id = f.silver_invoice_id
where existing.silver_invoice_id is null                       -- new key → insert
   or existing.silver_row_hash is distinct from f.silver_row_hash  -- changed → update
{% endif %}
