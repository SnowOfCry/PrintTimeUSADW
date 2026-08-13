-- DQ (referential, the payoff integrity): every month that has retail sales must
-- have a CPI value AT OR BEFORE it, so bi_revenue_real can deflate it (directly or
-- by forward-filling an occasional FRED gap, e.g. the missing Oct-2025 CPI). Fails
-- only if a revenue month has no deflation basis at all.
with rev_months as (
    select distinct (date_key / 100) as month_key from {{ ref('fact_retail_sales') }}
),
cpi_months as (
    select (extract(year from silver_observation_date) * 100
            + extract(month from silver_observation_date))::int as month_key
    from {{ ref('econ_indicator') }}
    where silver_series_id = 'CPIAUCSL' and silver_indicator_value is not null
)
select r.month_key
from rev_months r
where not exists (
    select 1 from cpi_months c where c.month_key <= r.month_key
)
