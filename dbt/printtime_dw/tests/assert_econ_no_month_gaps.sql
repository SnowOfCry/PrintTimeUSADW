-- DQ: each monthly series has an observation for every month between its first and
-- last date (no missing months — a gap would silently drop a deflation factor).
with bounds as (
    select silver_series_id, min(silver_observation_date) lo, max(silver_observation_date) hi
    from {{ ref('econ_indicator') }} group by 1
),
expected as (
    select b.silver_series_id, cast(gs as date) as month
    from bounds b
    lateral view explode(sequence(b.lo, b.hi, interval 1 month)) as gs
)
select e.silver_series_id, e.month
from expected e
left join {{ ref('econ_indicator') }} s
    on s.silver_series_id = e.silver_series_id
   and trunc(s.silver_observation_date, 'MM') = trunc(e.month, 'MM')
where s.silver_series_id is null
