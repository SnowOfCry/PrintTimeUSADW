-- =============================================================================
-- gold.bi_revenue_real — nominal vs. REAL (inflation-adjusted) monthly revenue.
-- -----------------------------------------------------------------------------
-- The payoff of the FRED source (ADR-020): deflate monthly revenue by CPI so
-- "growth" is separated from inflation. Real revenue is expressed in the dollars
-- of the LATEST CPI month in the revenue window (i.e. today's dollars):
--     real = nominal * (base_cpi / month_cpi)
-- Joins fact_retail_sales (gold) to silver.econ_indicator (CPI). It reads silver
-- by design — the conformed series lives there and is immutable reference data —
-- but is owned by pt_dbt, so the BI role only ever sees the aggregated result.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi', 'econ']) }}

with monthly as (
    select
        (date_key / 100)        as month_key,       -- YYYYMM from the YYYYMMDD date_key
        sum(sales_amount)       as nominal_revenue
    from {{ ref('fact_retail_sales') }}
    group by 1
),

cpi_raw as (
    select
        (extract(year from silver_observation_date) * 100
         + extract(month from silver_observation_date))::int as month_key,
        silver_indicator_value                                as cpi
    from {{ ref('econ_indicator') }}
    where silver_series_id = 'CPIAUCSL'
),

-- Forward-fill occasional FRED gaps (e.g. CPI-U had no Oct-2025 value): a month
-- with no published index carries the last-known one, so no revenue month is
-- dropped for a missing deflator.
cpi as (
    select
        r.month_key,
        coalesce(
            r.cpi,
            (select r2.cpi from cpi_raw r2
             where r2.month_key < r.month_key and r2.cpi is not null
             order by r2.month_key desc limit 1)
        ) as cpi
    from cpi_raw r
),

-- Base = the latest CPI month that overlaps the revenue window (today's dollars).
base as (
    select c.cpi as base_cpi
    from cpi c
    join monthly m on m.month_key = c.month_key
    order by c.month_key desc
    limit 1
)

select
    m.month_key,
    m.nominal_revenue,
    c.cpi                                                  as cpi_index,
    b.base_cpi,
    round(m.nominal_revenue * (b.base_cpi / c.cpi), 2)     as real_revenue,
    round((b.base_cpi / c.cpi - 1) * 100, 2)               as inflation_uplift_pct
from monthly m
join cpi c  on c.month_key = m.month_key
cross join base b
order by m.month_key
