-- =============================================================================
-- gold.dim_invoice
-- Type:    SCD Type 2 dimension (versioned history) — the ADR-015 pattern.
-- Grain:   one row per invoice VERSION (current version: is_current = true).
-- Source:  silver.invoice; lookups: silver.customer, silver.store
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_invoice)
--          docs/source_to_dw_mapping/Silver_to_Gold_mapping.md §8
--          ADR-007 (Type 2), ADR-015 (SCD2 pattern), ADR-011 (-1 member)
--
-- Notes specific to this dim:
--   * STANDARD Type 2 from silver.invoice (gold decision #2) — deliberately NOT
--     rebuilt from silver.invoice_status_history, which records status timing but
--     cannot reconstruct historical totals. That history table stays the
--     authoritative source for exact status-duration analysis (backlog #11).
--   * The most volatile dimension: the open -> partial -> paid/void lifecycle and
--     the running total/paid amounts mean invoices version more than any other
--     dim. Fidelity is bounded by gold run frequency (ADR-007) — a daily run
--     captures the days-to-weeks lifecycle in practice.
--   * po_number added during the gold build (backlog #10): 30% of invoices carry
--     a customer PO, and BI needs to group payments by it.
--   * invoice_total narrows from silver numeric(18,2) to gold numeric(12,2)
--     (backlog #6). Verified safe: max total is 196,382.98, far below the
--     ~10^10 limit, so no invoice can overflow.
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
               etl_updated_timestamp = current_timestamp
        from   {{ this }} nv
        where  nv.source_record_id = d.source_record_id
          and  nv.row_version      = d.row_version + 1
          and  d.is_current
          and  d.invoice_key <> -1
        "
    ]
) }}

-- 1) Read silver and denormalize the customer + store descriptors.
with staged as (
    select
        i.silver_invoice_id::varchar(100)                       as source_record_id,
        i.silver_invoice_number::varchar(30)                    as invoice_number,
        i.silver_po_number::varchar(50)                         as po_number,
        i.silver_invoice_date::date                             as invoice_date,
        i.silver_invoice_status::varchar(20)                    as invoice_status,
        i.silver_total_amount::numeric(12,2)                    as invoice_total,
        c.silver_customer_account_no::varchar(30)               as customer_id,
        c.silver_customer_name::varchar(100)                    as customer_name,
        s.silver_store_code::varchar(30)                        as store_id,
        s.silver_store_name::varchar(100)                       as store_name,
        i.silver_is_deleted_flag::boolean                       as is_deleted,
        i.silver_source_system::varchar(50)                     as source_system,
        -- Effective-dating input (audit HIGH-3): a new version is dated by the
        -- source update instant, not the load date.
        i.silver_source_updated_at_timestamp                    as src_updated_at,
        -- SHA-256 over the TRACKED attributes only: status and total changes are
        -- what drive new versions here.
        encode(digest(concat_ws('|',
            coalesce(i.silver_invoice_number, ''),
            coalesce(i.silver_po_number, ''),
            coalesce(i.silver_invoice_date::text, ''),
            coalesce(i.silver_invoice_status, ''),
            coalesce(i.silver_total_amount::text, ''),
            coalesce(c.silver_customer_account_no, ''),
            coalesce(c.silver_customer_name, ''),
            coalesce(s.silver_store_code, ''),
            coalesce(s.silver_store_name, ''),
            coalesce(i.silver_is_deleted_flag::text, '')
        ), 'sha256'), 'hex')::char(64)                          as record_hash
    from {{ ref('invoice') }} i
    left join {{ ref('customer') }} c
           on c.silver_customer_id = i.silver_customer_id
    left join {{ ref('store') }} s
           on s.silver_store_id = i.silver_store_id
),

-- 2) Emit only rows needing a NEW version: new invoice, or changed hash vs. the
--    entity's current version. Unchanged invoices emit nothing.
changed as (
    select
        s.*
        {% if is_incremental() %}
        , c.row_version as current_row_version
        {% else %}
        , 0::integer    as current_row_version
        {% endif %}
    from staged s
    {% if is_incremental() %}
    left join {{ this }} c
           on c.source_record_id = s.source_record_id
          and c.is_current
    where c.source_record_id is null                      -- brand-new invoice
       or c.record_hash is distinct from s.record_hash    -- genuinely changed
    {% endif %}
),

-- 3) dbt-managed surrogate key (decision #7): each emitted row is a new version,
--    so it gets a fresh key = (highest key so far) + its position.
keyed as (
    select
        (
            {% if is_incremental() %}
            (select coalesce(max(invoice_key), 0) from {{ this }} where invoice_key <> -1)
            {% else %}
            0
            {% endif %}
            + row_number() over (order by source_record_id)
        )::integer                                      as invoice_key,
        (current_row_version + 1)::integer              as row_version,
        c.*
    from changed c
),

final as (
    select
        invoice_key,
        invoice_number,
        po_number,
        invoice_date,
        invoice_status,
        invoice_total,
        customer_id,
        customer_name,
        store_id,
        store_name,
        record_hash,
        source_system,
        source_record_id,
        null::varchar(50)               as etl_batch_id,
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
    -1::integer, 'Not Provided'::varchar(30), 'Not Provided'::varchar(50),
    null::date, 'Not Provided'::varchar(20), null::numeric(12,2),
    'Not Provided'::varchar(30), 'Not Provided'::varchar(100),
    'Not Provided'::varchar(30), 'Not Provided'::varchar(100),
    null::char(64), 'system'::varchar(50), '-1'::varchar(100), null::varchar(50),
    current_timestamp::timestamp, current_timestamp::timestamp,
    date '1900-01-01', null::date, true, 1,   -- -1 member: open-ended sentinel window
    true, false, false, null::varchar(500), false, null::timestamp
{% endif %}
