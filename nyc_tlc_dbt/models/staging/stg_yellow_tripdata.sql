-- One row per raw trip record, with clean names and types.
-- The TLC data has no trip ID, so trip_id is a hash of the record's fields.
-- Exact duplicate records share a trip_id; quality.trips_checked flags them.

with source as (

    select * from {{ source('nyc_tlc', 'yellow_tripdata') }}

),

renamed as (

    select
        cast(vendor_id as integer)                 as vendor_id,
        cast(tpep_pickup_datetime as timestamp)    as pickup_at,
        cast(tpep_dropoff_datetime as timestamp)   as dropoff_at,
        cast(passenger_count as integer)           as passenger_count,
        cast(trip_distance as double)              as trip_distance_miles,
        cast(ratecode_id as integer)               as rate_code_id,
        store_and_fwd_flag,
        cast(pu_location_id as integer)            as pickup_location_id,
        cast(do_location_id as integer)            as dropoff_location_id,
        cast(payment_type as integer)              as payment_type_id,
        cast(fare_amount as decimal(12, 2))           as fare_amount,
        cast(extra as decimal(12, 2))                 as extra,
        cast(mta_tax as decimal(12, 2))               as mta_tax,
        cast(tip_amount as decimal(12, 2))            as tip_amount,
        cast(tolls_amount as decimal(12, 2))          as tolls_amount,
        cast(improvement_surcharge as decimal(12, 2)) as improvement_surcharge,
        cast(congestion_surcharge as decimal(12, 2))  as congestion_surcharge,
        cast(airport_fee as decimal(12, 2))           as airport_fee,
        cast(cbd_congestion_fee as decimal(12, 2))    as cbd_congestion_fee,
        cast(total_amount as decimal(12, 2))          as total_amount,
        source_file,
        regexp_extract(source_file, '(\d{4}-\d{2})', 1) as source_year_month
    from source

)

select
    md5(concat_ws('|',
        source_file,
        coalesce(cast(vendor_id as varchar), ''),
        coalesce(cast(pickup_at as varchar), ''),
        coalesce(cast(dropoff_at as varchar), ''),
        coalesce(cast(pickup_location_id as varchar), ''),
        coalesce(cast(dropoff_location_id as varchar), ''),
        coalesce(cast(passenger_count as varchar), ''),
        coalesce(cast(trip_distance_miles as varchar), ''),
        coalesce(cast(rate_code_id as varchar), ''),
        coalesce(cast(payment_type_id as varchar), ''),
        coalesce(cast(fare_amount as varchar), ''),
        coalesce(cast(tip_amount as varchar), ''),
        coalesce(cast(total_amount as varchar), '')
    )) as trip_id,
    *
from renamed
