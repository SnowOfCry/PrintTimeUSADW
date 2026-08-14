-- =============================================================================
-- gold.bi_margin_vs_paper_cost — monthly gross margin vs. the paper-cost index.
-- -----------------------------------------------------------------------------
-- Second FRED payoff (ADR-020): the shop's COGS is dominated by paper, so track
-- monthly gross margin against the PPI for pulp/paper (WPU0911). Rising paper PPI
-- with falling margin is real input-cost pressure — the kind of driver a finance
-- team watches. Reads fact_retail_sales (gold) + silver.econ_indicator (PPI);
-- pt_dbt-owned, so the BI role sees only the aggregate.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi', 'econ']) }}

with monthly as (
    select
        (date_key / 100)        as month_key,
        sum(sales_amount)       as revenue,
        sum(gross_profit)       as gross_profit,
        case when sum(sales_amount) <> 0
             then round(sum(gross_profit) / sum(sales_amount) * 100, 2)
        end                     as gross_margin_pct
    from {{ ref('fact_retail_sales') }}
    group by 1
),

ppi_raw as (
    select
        (extract(year from silver_observation_date) * 100
         + extract(month from silver_observation_date))::int as month_key,
        silver_indicator_value                                as paper_ppi
    from {{ ref('econ_indicator') }}
    where silver_series_id = 'WPU0911'
),

-- Forward-fill any FRED gap (symmetric with bi_revenue_real's CPI handling) so a
-- missing PPI month never leaves a hole in the margin-vs-cost trend.
ppi as (
    select
        r.month_key,
        coalesce(
            r.paper_ppi,
            (select r2.paper_ppi from ppi_raw r2
             where r2.month_key < r.month_key and r2.paper_ppi is not null
             order by r2.month_key desc limit 1)
        ) as paper_ppi
    from ppi_raw r
)

select
    m.month_key,
    m.revenue,
    m.gross_profit,
    m.gross_margin_pct,
    p.paper_ppi
from monthly m
left join ppi p on p.month_key = m.month_key
order by m.month_key
