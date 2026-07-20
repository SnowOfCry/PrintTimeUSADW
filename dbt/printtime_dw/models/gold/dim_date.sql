-- =============================================================================
-- gold.dim_date
-- Type:    conformed calendar dimension (Kimball). Load = Type 0 (generate once,
--          extend forward). No silver source — deterministically generated.
-- Grain:   one row per calendar date. date_key is a smart YYYYMMDD key.
-- Spec:    sql/gold/002_create_gold_tables.sql (gold.dim_date)
--          docs/data_dictionary/gold_data_dictionary.md (attribute formats)
--          docs/load_strategy/gold_load_strategy.md (Type 0), ADR-010 (role-playing views)
-- Decisions (this build):
--   - range 2020-01-01 .. 2030-12-31 (brackets the 2023-2025 data + future/growth)
--   - calendar_week_ending_date = the week's Saturday (US retail convention)
--   - holiday_indicator = US federal holidays incl. floating; else 'None'
--   - a -1 "Not Provided" member (ADR-011) for unknown/optional date FKs;
--     date is NOT NULL so the member uses the sentinel 1900-01-01.
-- =============================================================================
{{ config(materialized='table') }}

with spine as (
    select generate_series(date '2020-01-01', date '2030-12-31', interval '1 day')::date as date
),

calendar as (
    select
        (to_char(date, 'YYYYMMDD'))::integer                                              as date_key,
        date                                                                              as date,
        (to_char(date, 'FMMonth') || ' ' || extract(day from date)::int
            || ', ' || extract(year from date)::int)::varchar(50)                         as full_date_description,
        (to_char(date, 'FMDay'))::varchar(10)                                             as day_of_week,
        extract(day from date)::smallint                                                  as day_number_in_calendar_month,
        (case when date = (date_trunc('month', date) + interval '1 month - 1 day')::date
              then 'Yes' else 'No' end)::varchar(3)                                        as last_day_in_month_indicator,
        -- Week ends on Saturday (dow: 0=Sun .. 6=Sat): add days to reach the next Saturday.
        (date + ((6 - extract(dow from date)::int + 7) % 7))::date                         as calendar_week_ending_date,
        (to_char(date, 'FMMonth'))::varchar(10)                                            as calendar_month_name,
        extract(month from date)::smallint                                                as calendar_month_number_in_year,
        extract(quarter from date)::smallint                                              as calendar_quarter,
        (to_char(date, 'YYYY') || '-Q' || extract(quarter from date)::int)::varchar(7)     as calendar_year_quarter,
        extract(year from date)::smallint                                                 as calendar_year,
        (to_char(date, 'YYYY-MM'))::varchar(7)                                             as calendar_year_month,
        -- US federal holidays (fixed + floating); everything else 'None'.
        (case
            when extract(month from date) = 1  and extract(day from date) = 1                                          then 'New Year''s Day'
            when extract(month from date) = 1  and extract(dow from date) = 1 and extract(day from date) between 15 and 21 then 'MLK Day'
            when extract(month from date) = 2  and extract(dow from date) = 1 and extract(day from date) between 15 and 21 then 'Presidents'' Day'
            when extract(month from date) = 5  and extract(dow from date) = 1 and extract(day from date) between 25 and 31 then 'Memorial Day'
            when extract(month from date) = 6  and extract(day from date) = 19                                         then 'Juneteenth'
            when extract(month from date) = 7  and extract(day from date) = 4                                          then 'Independence Day'
            when extract(month from date) = 9  and extract(dow from date) = 1 and extract(day from date) between 1 and 7   then 'Labor Day'
            when extract(month from date) = 10 and extract(dow from date) = 1 and extract(day from date) between 8 and 14  then 'Columbus Day'
            when extract(month from date) = 11 and extract(day from date) = 11                                         then 'Veterans Day'
            when extract(month from date) = 11 and extract(dow from date) = 4 and extract(day from date) between 22 and 28 then 'Thanksgiving'
            when extract(month from date) = 12 and extract(day from date) = 25                                         then 'Christmas Day'
            else 'None'
        end)::varchar(20)                                                                 as holiday_indicator,
        (case when extract(dow from date) in (0, 6) then 'Weekend' else 'Weekday' end)::varchar(10) as weekday_indicator,
        current_timestamp::timestamp                                                      as etl_load_timestamp,
        current_timestamp::timestamp                                                      as etl_updated_timestamp
    from spine
),

-- -1 "Not Provided" member (ADR-011) so facts with an unknown/optional date FK
-- resolve to a real row, never NULL. date is NOT NULL → sentinel 1900-01-01.
not_provided as (
    select
        -1::integer                     as date_key,
        date '1900-01-01'               as date,
        'Not Provided'::varchar(50)     as full_date_description,
        'Unknown'::varchar(10)          as day_of_week,
        null::smallint                  as day_number_in_calendar_month,
        null::varchar(3)                as last_day_in_month_indicator,
        null::date                      as calendar_week_ending_date,
        'Unknown'::varchar(10)          as calendar_month_name,
        null::smallint                  as calendar_month_number_in_year,
        null::smallint                  as calendar_quarter,
        'Unknown'::varchar(7)           as calendar_year_quarter,
        null::smallint                  as calendar_year,
        'Unknown'::varchar(7)           as calendar_year_month,
        'None'::varchar(20)             as holiday_indicator,
        'Unknown'::varchar(10)          as weekday_indicator,
        current_timestamp::timestamp    as etl_load_timestamp,
        current_timestamp::timestamp    as etl_updated_timestamp
)

select * from calendar
union all
select * from not_provided
