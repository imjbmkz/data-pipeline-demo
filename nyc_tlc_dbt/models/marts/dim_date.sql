-- One row per calendar day covered by the passed trips (pickup to dropoff).

with bounds as (

    select
        min(cast(pickup_at as date))  as first_date,
        max(cast(dropoff_at as date)) as last_date
    from {{ ref('trips_passed') }}

),

days as (

    select
        unnest(generate_series(
            cast(first_date as timestamp),
            cast(last_date as timestamp),
            interval 1 day
        )) as day_ts
    from bounds

),

dates as (

    select cast(day_ts as date) as date_day
    from days

)

select
    cast(strftime(date_day, '%Y%m%d') as integer) as date_key,
    date_day,
    year(date_day)          as year,
    quarter(date_day)       as quarter,
    month(date_day)         as month,
    monthname(date_day)     as month_name,
    day(date_day)           as day_of_month,
    isodow(date_day)        as day_of_week,   -- 1 = Monday, 7 = Sunday
    dayname(date_day)       as day_name,
    isodow(date_day) in (6, 7) as is_weekend
from dates
