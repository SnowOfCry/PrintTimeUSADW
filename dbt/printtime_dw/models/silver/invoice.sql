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
        invoice_id::bigint                                                            as silver_invoice_id,
        nullif(trim(invoice_number), '')::varchar(30)                                 as silver_invoice_number,
        customer_id::bigint                                                           as silver_customer_id,
        store_id::bigint                                                              as silver_store_id,
        employee_id::bigint                                                           as silver_employee_id,
        billing_address_id::bigint                                                    as silver_billing_address_id,
        shipping_address_id::bigint                                                   as silver_shipping_address_id,
        nullif(trim(po_number), '')::varchar(50)                                      as silver_po_number,
        invoice_date::date                                                            as silver_invoice_date,
        invoice_due_date::date                                                        as silver_invoice_due_date,
        -- Closed lower-case invoice-status vocabulary (ADR-005 #4); unmapped -> NULL.
        case lower(trim(invoice_status))
            when 'open'    then 'open'
            when 'partial' then 'partial'
            when 'paid'    then 'paid'
            when 'void'    then 'void'
            else null
        end::varchar(20)                                                              as silver_invoice_status,
        tax_rate_id::bigint                                                           as silver_tax_rate_id,
        subtotal_amount::numeric(18,2)                                                as silver_subtotal_amount,
        discount_amount::numeric(18,2)                                                as silver_discount_amount,
        tax_amount::numeric(18,2)                                                     as silver_tax_amount,
        fee_amount::numeric(18,2)                                                     as silver_fee_amount,
        total_amount::numeric(18,2)                                                   as silver_total_amount,
        paid_amount::numeric(18,2)                                                    as silver_paid_amount,
        balance_due_amount::numeric(18,2)                                             as silver_balance_due_amount,
        -- Derived business flags (ADR-005 #5), computed from the raw amounts so
        -- they cannot reference the silver aliases defined in this same SELECT.
        (balance_due_amount > 0)::boolean                                             as silver_has_balance_due_flag,
        (paid_amount >= total_amount)::boolean                                        as silver_paid_in_full_flag,
        nullif(regexp_replace(trim(notes), '\s+', ' ', 'g'), '')::varchar(1000)       as silver_notes,

        -- ── source lineage carried forward from bronze ──────────────────────
        bronze_source_system::varchar(100)         as silver_source_system,
        bronze_source_table_name::varchar(150)     as silver_source_table_name,
        invoice_id::text                           as silver_source_record_id,
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
                silver_invoice_id::text,
                coalesce(silver_invoice_number, ''),
                coalesce(silver_customer_id::text, ''),
                coalesce(silver_store_id::text, ''),
                coalesce(silver_employee_id::text, ''),
                coalesce(silver_billing_address_id::text, ''),
                coalesce(silver_shipping_address_id::text, ''),
                coalesce(silver_po_number, ''),
                coalesce(silver_invoice_date::text, ''),
                coalesce(silver_invoice_due_date::text, ''),
                coalesce(silver_invoice_status, ''),
                coalesce(silver_tax_rate_id::text, ''),
                coalesce(silver_subtotal_amount::text, ''),
                coalesce(silver_discount_amount::text, ''),
                coalesce(silver_tax_amount::text, ''),
                coalesce(silver_fee_amount::text, ''),
                coalesce(silver_total_amount::text, ''),
                coalesce(silver_paid_amount::text, ''),
                coalesce(silver_balance_due_amount::text, ''),
                coalesce(silver_has_balance_due_flag::text, ''),
                coalesce(silver_paid_in_full_flag::text, ''),
                coalesce(silver_notes, '')
            )
        )::text as silver_row_hash
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
