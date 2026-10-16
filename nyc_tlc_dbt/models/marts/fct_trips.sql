-- One row per trip that passed every quality check.

select
    trip_id,

    -- Dimension keys
    cast(strftime(pickup_at, '%Y%m%d') as integer)  as pickup_date_key,
    cast(strftime(dropoff_at, '%Y%m%d') as integer) as dropoff_date_key,
    vendor_id,
    coalesce(rate_code_id, 99)                      as rate_code_id,
    payment_type_id,
    pickup_location_id,
    dropoff_location_id,

    -- Trip details
    pickup_at,
    dropoff_at,
    round(date_diff('second', pickup_at, dropoff_at) / 60.0, 2) as trip_duration_minutes,
    passenger_count,
    trip_distance_miles,
    store_and_fwd_flag = 'Y'                        as is_store_and_forward,

    -- Amounts (USD)
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,
    total_amount,

    source_file
from {{ ref('trips_passed') }}
