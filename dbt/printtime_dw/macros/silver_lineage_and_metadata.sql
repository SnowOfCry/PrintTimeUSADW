{#
    silver_lineage_and_metadata(source_record_id, source_created_at, source_updated_at)

    Renders the 11-column lineage + metadata block that closes every silver
    model's cleaning SELECT — the audit trail carried forward from bronze plus
    silver's own stamping. Ten of the eleven columns were byte-identical across
    all 20 models; centralizing them here means a change to the audit shape is
    one edit instead of twenty, and no model can drift from the others.

    Only three columns vary by model, so they are parameters:
      source_record_id   the natural/business key, cast to ::text as
                         silver_source_record_id (required — every model differs)
      source_created_at  bronze column feeding silver_source_created_at_timestamp
                         (defaults to created_at_source_timestamp; the history
                         tables pass changed_at_source_timestamp — they have no
                         created/updated, only a change instant)
      source_updated_at  likewise for silver_source_updated_at_timestamp

    PLACEMENT: renders 11 columns with NO trailing comma, so it must be the LAST
    item in the SELECT list. The business columns before it keep their trailing
    comma; nothing follows it but `from ...`. The change-detection hash is
    intentionally NOT here — it is computed over business columns only, in a
    later CTE, so metadata never registers as a change (see any silver model).
#}
{%- macro silver_lineage_and_metadata(
        source_record_id,
        source_created_at='created_at_source_timestamp',
        source_updated_at='updated_at_source_timestamp'
) -%}
        -- ── source lineage carried forward from bronze ──────────────────────
        cast(bronze_source_system     as string)    as silver_source_system,
        cast(bronze_source_table_name as string)    as silver_source_table_name,
        cast({{ source_record_id }}   as string)    as silver_source_record_id,
        cast({{ source_created_at }}  as timestamp) as silver_source_created_at_timestamp,
        cast({{ source_updated_at }}  as timestamp) as silver_source_updated_at_timestamp,
        cast(bronze_record_id         as bigint)    as silver_bronze_record_id,
        cast(bronze_batch_id          as bigint)    as silver_bronze_batch_id,

        -- ── silver's own metadata (stamped as this row is built) ────────────
        cast({{ require_batch_id('silver_batch_id') }} as bigint) as silver_batch_id,
        current_timestamp()                         as silver_created_at_timestamp,
        current_timestamp()                         as silver_updated_at_timestamp,
        cast(bronze_is_deleted_flag   as boolean)   as silver_is_deleted_flag
{%- endmacro -%}
