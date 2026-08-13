-- DQ: one silver row per (series_id, observation_date). Fails if the grain duplicates.
select silver_series_id, silver_observation_date, count(*) as n
from {{ ref('econ_indicator') }}
group by 1, 2
having count(*) > 1
