-- =============================================================================
-- Singular test: each SCD2 entity's row_version set is exactly {1, 2, …, N}.
-- -----------------------------------------------------------------------------
-- Guards the SCD2 versioning (ADR-015 / audit MED-5). Each entity's versions
-- must be numbered contiguously from 1 with no gaps and no duplicates. A gap or
-- duplicate means a version was lost or double-inserted (e.g. a half-applied
-- append + post-hook on a mid-run failure), which corrupts the version history.
--
-- Fails (returns rows) for any entity whose versions are NOT {1..N}:
--   count(*) <> max(row_version)          -> a gap (or a duplicate lowering N)
--   count(distinct row_version) <> count  -> a duplicate version number
--   min(row_version) <> 1                 -> does not start at 1
-- The -1 member is excluded (it is a single seeded row, row_version = 1).
-- =============================================================================
{% set scd2_dims = [
    'dim_customer', 'dim_store', 'dim_cashier',
    'dim_product', 'dim_invoice', 'dim_payment_method'
] %}

{% for d in scd2_dims %}
select
    '{{ d }}'                    as dimension,
    source_record_id,
    count(*)                     as version_count,
    max(row_version)             as max_version
from {{ ref(d) }}
where source_record_id <> '-1'
group by source_record_id
having count(*) <> max(row_version)
    or count(distinct row_version) <> count(*)
    or min(row_version) <> 1
{% if not loop.last %}union all{% endif %}
{% endfor %}
