-- =============================================================================
-- Singular test: no SCD2 entity has two versions whose validity windows overlap.
-- -----------------------------------------------------------------------------
-- Guards the SCD2 append + close-old-version pattern (ADR-015 / audit MED-5).
-- Versions must tile time as contiguous, non-overlapping half-open windows
-- [valid_from, valid_to). Two overlapping windows for one source_record_id mean
-- a version was left open when it should have been closed — e.g. a post-hook
-- that failed to close the prior version, leaving TWO current rows. That is the
-- exact state that makes a fact's effective-date join fan out and insert
-- duplicate rows, so this test gates the watermark (HIGH-7) before that happens.
--
-- Overlap (half-open): a.valid_from < b.valid_to AND b.valid_from < a.valid_to,
-- with NULL valid_to (an open/current version) treated as +infinity. Contiguous
-- windows (a.valid_to = b.valid_from) do NOT overlap and are fine.
--
-- Fails (returns rows) if any overlapping pair exists. The -1 member is excluded.
-- =============================================================================
{% set scd2_dims = [
    'dim_customer', 'dim_store', 'dim_cashier',
    'dim_product', 'dim_invoice', 'dim_payment_method'
] %}

{% for d in scd2_dims %}
select
    '{{ d }}'              as dimension,
    a.source_record_id,
    a.row_version          as version_a,
    b.row_version          as version_b
from {{ ref(d) }} a
join {{ ref(d) }} b
  on  b.source_record_id = a.source_record_id
  and a.row_version      < b.row_version
where a.source_record_id <> '-1'
  and a.valid_from < coalesce(b.valid_to, 'infinity'::date)
  and b.valid_from < coalesce(a.valid_to, 'infinity'::date)
{% if not loop.last %}union all{% endif %}
{% endfor %}
