-- =============================================================================
-- gold.bi_dim_date — conformed DATE dimension for BI (ADR-017)
-- The single date dimension shared by every fact (sales, payments, snapshot),
-- so one date slicer cross-filters all of them. Calendar attributes only;
-- audit/DQ plumbing hidden. Role-playing extra date roles (last order, first
-- order) use the vw_*_date views (ADR-010).
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    date_key,
    date,
    full_date_description,
    day_of_week,
    day_number_in_calendar_month,
    last_day_in_month_indicator,
    calendar_week_ending_date,
    calendar_month_name,
    calendar_month_number_in_year,
    calendar_quarter,
    calendar_year_quarter,
    calendar_year,
    calendar_year_month,
    holiday_indicator,
    weekday_indicator
from {{ ref('dim_date') }}
