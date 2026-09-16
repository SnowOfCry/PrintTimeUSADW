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
-- Databricks port notes (Postgres -> Spark SQL):
--   - generate_series(...)         -> explode(sequence(..., interval 1 day))
--   - to_char(d, 'FMMonth'/'FMDay')-> date_format(d, 'MMMM'/'EEEE')
--   - to_char(d, 'YYYYMMDD' etc.)  -> date_format(d, 'yyyyMMdd' etc.)
--   - date_trunc('month', d) + interval '1 month - 1 day' -> last_day(d)
--   - extract(dow from d)   Postgres 0=Sun..6=Sat  ==  dayofweek(d) - 1 in Spark
--   - d + n (add days)             -> date_add(d, n)
-- =============================================================================
{{ config(
    materialized='table'
) }}

with spine as (
    select explode(sequence(date'2020-01-01', date'2030-12-31', interval 1 day)) as date
),

calendar as (
    select
        cast(date_format(date, 'yyyyMMdd') as int)                                        as date_key,
        date                                                                              as date,
        cast((date_format(date, 'MMMM') || ' ' || cast(extract(day from date) as int)
            || ', ' || cast(extract(year from date) as int)) as string)                   as full_date_description,
        cast(date_format(date, 'EEEE') as string)                                         as day_of_week,
        cast(extract(day from date) as smallint)                                          as day_number_in_calendar_month,
        cast((case when date = last_day(date) then 'Yes' else 'No' end) as string)        as last_day_in_month_indicator,
        -- Week ends on Saturday. Postgres dow (0=Sun..6=Sat) == dayofweek(date) - 1.
        cast(date_add(date, (6 - (dayofweek(date) - 1) + 7) % 7) as date)                 as calendar_week_ending_date,
        cast(date_format(date, 'MMMM') as string)                                         as calendar_month_name,
        cast(extract(month from date) as smallint)                                        as calendar_month_number_in_year,
        cast(extract(quarter from date) as smallint)                                      as calendar_quarter,
        cast((date_format(date, 'yyyy') || '-Q' || cast(extract(quarter from date) as int)) as string) as calendar_year_quarter,
        cast(extract(year from date) as smallint)                                         as calendar_year,
        cast(date_format(date, 'yyyy-MM') as string)                                      as calendar_year_month,
        -- US federal holidays (fixed + floating); everything else 'None'.
        cast((case
            when extract(month from date) = 1  and extract(day from date) = 1                                                    then 'New Year''s Day'
            when extract(month from date) = 1  and (dayofweek(date) - 1) = 1 and extract(day from date) between 15 and 21        then 'MLK Day'
            when extract(month from date) = 2  and (dayofweek(date) - 1) = 1 and extract(day from date) between 15 and 21        then 'Presidents'' Day'
            when extract(month from date) = 5  and (dayofweek(date) - 1) = 1 and extract(day from date) between 25 and 31        then 'Memorial Day'
            when extract(month from date) = 6  and extract(day from date) = 19                                                   then 'Juneteenth'
            when extract(month from date) = 7  and extract(day from date) = 4                                                    then 'Independence Day'
            when extract(month from date) = 9  and (dayofweek(date) - 1) = 1 and extract(day from date) between 1 and 7          then 'Labor Day'
            when extract(month from date) = 10 and (dayofweek(date) - 1) = 1 and extract(day from date) between 8 and 14         then 'Columbus Day'
            when extract(month from date) = 11 and extract(day from date) = 11                                                   then 'Veterans Day'
            when extract(month from date) = 11 and (dayofweek(date) - 1) = 4 and extract(day from date) between 22 and 28        then 'Thanksgiving'
            when extract(month from date) = 12 and extract(day from date) = 25                                                   then 'Christmas Day'
            else 'None'
        end) as string)                                                                   as holiday_indicator,
        cast((case when (dayofweek(date) - 1) in (0, 6) then 'Weekend' else 'Weekday' end) as string) as weekday_indicator,
        cast(current_timestamp() as timestamp)                                            as etl_load_timestamp,
        cast(current_timestamp() as timestamp)                                            as etl_updated_timestamp
    from spine
),

-- -1 "Not Provided" member (ADR-011) so facts with an unknown/optional date FK
-- resolve to a real row, never NULL. date is NOT NULL → sentinel 1900-01-01.
not_provided as (
    select
        -cast(1 as int)                     as date_key,
        date '1900-01-01'               as date,
        cast('Not Provided' as string)     as full_date_description,
        cast('Unknown' as string)          as day_of_week,
        cast(null as smallint)                  as day_number_in_calendar_month,
        cast(null as string)                as last_day_in_month_indicator,
        cast(null as date)                      as calendar_week_ending_date,
        cast('Unknown' as string)          as calendar_month_name,
        cast(null as smallint)                  as calendar_month_number_in_year,
        cast(null as smallint)                  as calendar_quarter,
        cast('Unknown' as string)           as calendar_year_quarter,
        cast(null as smallint)                  as calendar_year,
        cast('Unknown' as string)           as calendar_year_month,
        cast('None' as string)             as holiday_indicator,
        cast('Unknown' as string)          as weekday_indicator,
        cast(current_timestamp() as timestamp)    as etl_load_timestamp,
        cast(current_timestamp() as timestamp)    as etl_updated_timestamp
)

select * from calendar
union all
select * from not_provided
