-- DQ: CPI/PPI index values must be positive; a non-positive index is bad data.
select silver_series_id, silver_observation_date, silver_indicator_value
from {{ ref('econ_indicator') }}
where silver_indicator_value is not null and silver_indicator_value <= 0
