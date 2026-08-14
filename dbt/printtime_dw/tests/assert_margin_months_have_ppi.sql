-- DQ (referential, symmetric with assert_revenue_months_have_cpi): every month
-- that has retail sales must have a paper-PPI basis AT OR BEFORE it, so
-- bi_margin_vs_paper_cost has an index for every margin month (directly or by
-- forward-filling a FRED gap). Fails only if a revenue month has no PPI basis.
with rev_months as (
    select distinct (date_key / 100) as month_key from {{ ref('fact_retail_sales') }}
),
ppi_months as (
    select (extract(year from silver_observation_date) * 100
            + extract(month from silver_observation_date))::int as month_key
    from {{ ref('econ_indicator') }}
    where silver_series_id = 'WPU0911' and silver_indicator_value is not null
)
select r.month_key
from rev_months r
where not exists (
    select 1 from ppi_months c where c.month_key <= r.month_key
)
