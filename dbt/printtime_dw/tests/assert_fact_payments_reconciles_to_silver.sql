-- =============================================================================
-- Reconciliation gate: gold.fact_payments must tie out to its silver source
-- TO THE CENT — row count and total payment amount (refunds included, stored
-- negative, so the SUM nets correctly). A dbt SINGULAR test: returns rows only
-- when reconciliation FAILS, which fails the build and holds the gold watermark
-- in the DAG (tests gate the commit — HIGH-7).
-- =============================================================================
with gold as (
    select count(*) as n_rows,
           round(coalesce(sum(payment_amount), 0), 2) as total
    from {{ ref('fact_payments') }}
),
silver as (
    select count(*) as n_rows,
           round(coalesce(sum(silver_payment_amount), 0), 2) as total
    from {{ ref('payment') }}
)
select
    g.n_rows              as gold_rows,
    s.n_rows              as silver_rows,
    g.total               as gold_total,
    s.total               as silver_total,
    (g.total - s.total)   as total_diff
from gold g
cross join silver s
where g.n_rows <> s.n_rows
   or g.total  <> s.total
