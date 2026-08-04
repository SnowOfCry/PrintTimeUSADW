-- =============================================================================
-- Singular test: every SCD2 entity has EXACTLY ONE current version.
-- -----------------------------------------------------------------------------
-- Guards the effective-dating correction (ADR-015 / audit HIGH-3). The append +
-- close-old-version post-hook must leave precisely one is_current row per
-- source_record_id in each Type-2 dimension. If a post-hook ever fails to close
-- a superseded version (or closes the wrong one), an entity would have two open
-- versions and facts would fan out — this test fails the build if that happens.
--
-- Fails (returns rows) when any entity has 0 or >1 current versions.
-- The -1 "Not Provided" member is excluded (it is intentionally a single row).
-- =============================================================================
{% set scd2_dims = [
    'dim_customer', 'dim_store', 'dim_cashier',
    'dim_product', 'dim_invoice', 'dim_payment_method'
] %}

{% for d in scd2_dims %}
select
    '{{ d }}'                 as dimension,
    source_record_id,
    sum(is_current::int)      as current_versions
from {{ ref(d) }}
where source_record_id <> '-1'
group by source_record_id
having sum(is_current::int) <> 1
{% if not loop.last %}union all{% endif %}
{% endfor %}
