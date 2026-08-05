-- =============================================================================
-- audit_change_trail.sql — write audit.audit_log on gold fact reloads (MED-4)
-- -----------------------------------------------------------------------------
-- The two delete+insert facts DESTROY the old rows on a reload (SCD2 dims keep
-- their history in-table, so they don't need this — MED-4 is a facts-only gap).
-- These macros capture the before/after image of every replaced row into the
-- insert-only audit.audit_log (ADR-008), so "what was the old value, which batch
-- changed it, and why" is answerable by query.
--
-- Flow (all inside the model's single transaction — atomic with the reload):
--   pre_hook  audit_capture_before_image()  -> old_row of the rows about to be
--             deleted, operation UPDATE, change_reason, this run's etl_batch_id.
--   << dbt delete+insert replaces the rows >>
--   post_hook audit_fill_after_image()      -> matches each capture to its new
--             row by source_record_id, fills new_row + changed_columns; any
--             capture with no new row is reclassified DELETE.
-- =============================================================================

-- Last succeeded gold batch end for a target (the incremental watermark).
{% macro last_gold_watermark(target) -%}
(select coalesce(max(batch_end_timestamp), '1900-01-01'::timestamp)
 from audit.etl_batch_control
 where target_table = '{{ target }}' and batch_status = 'succeeded')
{%- endmacro %}


-- The invoice_numbers whose header OR any line changed since the last gold batch.
-- Shared by fact_retail_sales' incremental filter AND its before-image pre_hook,
-- so the captured rows are exactly the rows the reload replaces.
{% macro changed_invoice_numbers() -%}
select i2.silver_invoice_number
from {{ ref('invoice') }} i2
left join {{ ref('invoice_line') }} l2 on l2.silver_invoice_id = i2.silver_invoice_id
where i2.silver_updated_at_timestamp > {{ last_gold_watermark('gold.fact_retail_sales') }}
   or l2.silver_updated_at_timestamp > {{ last_gold_watermark('gold.fact_retail_sales') }}
{%- endmacro %}


-- The payment source ids changed since the last gold.fact_payments batch.
{% macro changed_payment_ids() -%}
select p.silver_payment_id::varchar(100)
from {{ ref('payment') }} p
where p.silver_updated_at_timestamp > {{ last_gold_watermark('gold.fact_payments') }}
{%- endmacro %}


-- pre_hook: STAGE the before-image of the rows about to be deleted into a
-- session-local temp table (audit.audit_log stays strictly insert-only per
-- ADR-008 — the row is written once, complete, by the post_hook below).
--   record_key    the {{ this }} column used as audit_log.record_key (reload unit)
--   match_col     the {{ this }} column whose values define the changed set
--   changed_set   SQL selecting the changed match_col values (a changed_* macro)
--   reason_sql    SQL expression (may reference alias f) for change_reason
{% macro audit_stage_before_image(record_key, match_col, changed_set, reason_sql="'source_update'") -%}
{% if is_incremental() %}
drop table if exists _audit_stage_{{ this.identifier }};
create temp table _audit_stage_{{ this.identifier }} as
select
    f.{{ record_key }}::varchar(100)       as record_key,
    to_jsonb(f)                            as old_row,
    (to_jsonb(f) ->> 'source_record_id')   as match_key,   -- pairs old row to its replacement
    ({{ reason_sql }})::varchar(500)       as change_reason,
    f.source_system                        as source_system
from {{ this }} f
where f.{{ match_col }} in (
    {{ changed_set }}
);
{% endif %}
{%- endmacro %}


-- change_reason for a retail-sales capture: best-effort from the invoice's
-- adjustment reason(s) in silver, else the generic 'source_update'. References
-- the pre_hook's fact alias f (f.invoice_number).
{% macro reason_from_invoice_adjustment() -%}
coalesce((select string_agg(distinct ia.silver_adjustment_reason, '; ')
          from {{ ref('invoice_adjustment') }} ia
          join {{ ref('invoice') }} i on i.silver_invoice_id = ia.silver_invoice_id
          where i.silver_invoice_number = f.invoice_number
            and ia.silver_adjustment_reason is not null), 'source_update')
{%- endmacro %}


-- post_hook: write ONE complete insert-only row per staged before-image, pairing
-- it to its replacement row (by the durable source_record_id) to fill new_row +
-- changed_columns. A stage row with no surviving fact row = a DELETE.
--   target          e.g. 'gold.fact_retail_sales'
--   surrogate_key   the fact's dbt-managed key (excluded from the diff: it is
--                   regenerated on every reload and is not a business change).
{% macro audit_write_change_log(target, surrogate_key) -%}
{% if is_incremental() %}
insert into audit.audit_log
    (table_name, operation_type, record_key, old_row, new_row, changed_columns,
     change_reason, etl_batch_id, source_system, changed_by_app_user)
select
    '{{ target }}',
    case when f.source_record_id is null then 'DELETE' else 'UPDATE' end,
    s.record_key,
    s.old_row,
    case when f.source_record_id is null then null else to_jsonb(f) end,
    -- which BUSINESS columns changed (exclude load metadata + the regenerated
    -- surrogate key, which always differ on a reload). NULL for a delete.
    case when f.source_record_id is null then null else (
        select jsonb_agg(o.key order by o.key)
        from jsonb_each_text(s.old_row) o
        where o.key not in ('{{ surrogate_key }}', 'etl_batch_id',
                            'etl_load_timestamp', 'etl_updated_timestamp')
          and o.value is distinct from (to_jsonb(f) ->> o.key)
    ) end,
    s.change_reason,
    '{{ gold_batch_id() }}'::varchar(50),
    s.source_system,
    'dbt:printtime_elt_pipeline'
from _audit_stage_{{ this.identifier }} s
left join {{ this }} f on f.source_record_id = s.match_key;

drop table if exists _audit_stage_{{ this.identifier }};
{% endif %}
{%- endmacro %}
