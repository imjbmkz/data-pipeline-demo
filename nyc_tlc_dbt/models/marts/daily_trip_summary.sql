-- One row per pickup day: trip volume, distance, duration and revenue.
-- Built from fct_trips, so it only counts trips that passed every quality check.

with trips as (

    select
        f.*,
        pt.payment_type_name,
        rc.rate_code_name,
        pz.borough as pickup_borough
    from {{ ref('fct_trips') }} as f
    left join {{ ref('dim_payment_type') }} as pt
        on f.payment_type_id = pt.payment_type_id
    left join {{ ref('dim_rate_code') }} as rc
        on f.rate_code_id = rc.rate_code_id
    left join {{ ref('dim_zone') }} as pz
        on f.pickup_location_id = pz.location_id

),

daily as (

    select
        pickup_date_key                                   as date_key,

        -- Volume
        count(*)                                          as total_trips,
        sum(passenger_count)                              as total_passengers,
        round(avg(passenger_count), 2)                    as avg_passengers_per_trip,

        -- Distance and duration
        round(sum(trip_distance_miles), 1)                as total_distance_miles,
        round(avg(trip_distance_miles), 2)                as avg_distance_miles,
        round(avg(trip_duration_minutes), 1)              as avg_duration_minutes,
        round(median(trip_duration_minutes), 1)           as median_duration_minutes,

        -- Revenue (USD)
        sum(fare_amount)                                  as total_fare_amount,
        sum(tip_amount)                                   as total_tip_amount,
        sum(total_amount)                                 as total_revenue,
        round(avg(total_amount), 2)                       as avg_revenue_per_trip,

        -- Tips are only recorded for card payments, so tip % uses card trips only
        round(
            100.0 * sum(tip_amount) filter (where payment_type_name = 'Credit card')
            / nullif(sum(fare_amount) filter (where payment_type_name = 'Credit card'), 0),
            2
        )                                                 as card_tip_pct_of_fare,

        -- Mix
        round(100.0 * count(*) filter (where payment_type_name = 'Credit card') / count(*), 2)
                                                          as credit_card_trip_pct,
        round(100.0 * count(*) filter (where payment_type_name = 'Cash') / count(*), 2)
                                                          as cash_trip_pct,
        count(*) filter (where rate_code_name in ('JFK', 'Newark'))
                                                          as airport_rate_trips,
        count(*) filter (where pickup_borough = 'Manhattan')
                                                          as manhattan_pickups

    from trips
    group by pickup_date_key

)

select
    d.date_key,
    d.date_day,
    d.day_name,
    d.is_weekend,
    d.month_name,
    daily.* exclude (date_key)
from daily
join {{ ref('dim_date') }} as d
    on daily.date_key = d.date_key
order by d.date_day
