-- DQ (freshness): each macro series must keep receiving new monthly observations.
-- FRED publishes monthly with a ~1-month lag, so a healthy feed's newest point is
-- ~30-75 days old; this flags a genuinely stalled feed or a broken pull at
-- **>95 days** (~3 months with no new data). Unlike the advisory source-freshness
-- SLA declared in `_bronze_sources.yml` (which nothing executes), this runs inside
-- the daily `dbt test` gate — so a stale FRED source actually alarms.
--
-- Empty-safe: no rows -> no groups -> passes (e.g. on a fresh CI build).
select
    silver_series_id,
    max(silver_observation_date)                 as latest_observation,
    current_date - max(silver_observation_date)  as days_stale
from {{ ref('econ_indicator') }}
group by silver_series_id
having current_date - max(silver_observation_date) > 95
