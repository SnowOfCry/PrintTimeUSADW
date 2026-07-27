{#
    role_playing_date_view(role)

    Generates a role-playing date view over gold.dim_date (ADR-010): the same
    conformed calendar re-labelled for one role, so a fact can join dim_date
    several times (invoice date, payment date, snapshot date, ...) without
    building a separate physical calendar per role.

    All three views in sql/gold/002_create_gold_tables.sql are identical apart
    from the column prefix, so the aliasing lives here once instead of being
    triplicated. Pass the role prefix, e.g.:

        {{ role_playing_date_view('first_order') }}   -> first_order_date_key, ...
        {{ role_playing_date_view('snapshot') }}      -> snapshot_date_key, ...
        {{ role_playing_date_view('last_order') }}    -> last_order_date_key, ...

    Column names must match the DDL exactly: <role>_date_key, <role>_date, and
    <role>_<attribute> for every remaining dim_date attribute.
#}
{% macro role_playing_date_view(role) %}

select
    date_key                      as {{ role }}_date_key,
    date                          as {{ role }}_date,
    full_date_description         as {{ role }}_full_date_description,
    day_of_week                   as {{ role }}_day_of_week,
    day_number_in_calendar_month  as {{ role }}_day_number_in_calendar_month,
    last_day_in_month_indicator   as {{ role }}_last_day_in_month_indicator,
    calendar_week_ending_date     as {{ role }}_calendar_week_ending_date,
    calendar_month_name           as {{ role }}_calendar_month_name,
    calendar_month_number_in_year as {{ role }}_calendar_month_number_in_year,
    calendar_quarter              as {{ role }}_calendar_quarter,
    calendar_year_quarter         as {{ role }}_calendar_year_quarter,
    calendar_year                 as {{ role }}_calendar_year,
    calendar_year_month           as {{ role }}_calendar_year_month,
    holiday_indicator             as {{ role }}_holiday_indicator,
    weekday_indicator             as {{ role }}_weekday_indicator
from {{ ref('dim_date') }}

{% endmacro %}
