-- =============================================================================
-- Reconciliation gate: gold.fact_retail_sales must tie out to its silver source
-- TO THE CENT — both the row count and the total sales amount.
--
-- This is a dbt SINGULAR test: it returns rows ONLY when reconciliation FAILS.
-- On failure the build fails, and because the Airflow DAG runs `dbt test` BEFORE
-- complete_gold_batches (HIGH-7), a reconciliation break HOLDS the gold watermark
-- and blocks the load instead of publishing a wrong number.
--
-- Catches: join fan-out (gold_total > silver_total), dropped rows
-- (gold_total < silver_total), and rounding/type-narrowing drift.
-- =============================================================================
with gold as (
    select count(*) as n_rows,
           round(coalesce(sum(sales_amount), 0), 2) as total
    from {{ ref('fact_retail_sales') }}
),
silver as (
    select count(*) as n_rows,
           round(coalesce(sum(silver_line_total_amount), 0), 2) as total
    from {{ ref('invoice_line') }}
)
select
    g.n_rows              as gold_rows,
    s.n_rows              as silver_rows,
    g.total               as gold_total,
    s.total               as silver_total,
    (g.total - s.total)   as total_diff
from gold g
cross join silver s
where g.n_rows <> s.n_rows        -- fan-out or dropped rows
   or g.total  <> s.total          -- amount drift (must match to the cent)
