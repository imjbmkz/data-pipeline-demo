-- Runs row-level quality checks on every trip.
-- Each check adds a dq_fail_<check> boolean; a trip passes when none are true.
-- trips_passed and trips_failed split this table on dq_failed_check_count.

{%- set checks = [
    'duplicate_trip',
    'missing_timestamp',
    'pickup_outside_file_month',
    'non_positive_duration',
    'excessive_duration',
    'invalid_trip_distance',
    'negative_amount',
    'invalid_passenger_count',
    'unknown_vendor',
    'unknown_payment_type',
    'unknown_rate_code',
    'unknown_pickup_zone',
    'unknown_dropoff_zone',
] %}

with trips as (

    select * from {{ ref('stg_yellow_tripdata') }}

),

zones as (

    select location_id from {{ ref('stg_taxi_zone_lookup') }}

),

flagged as (

    select
        trips.*,

        -- Keep the first copy of an exact duplicate record; flag the rest
        row_number() over (
            partition by trips.trip_id order by trips.pickup_at
        ) > 1
            as dq_fail_duplicate_trip,

        trips.pickup_at is null or trips.dropoff_at is null
            as dq_fail_missing_timestamp,

        -- Monthly files contain stray trips from other months and years
        coalesce(strftime(trips.pickup_at, '%Y-%m') <> trips.source_year_month, false)
            as dq_fail_pickup_outside_file_month,

        coalesce(trips.dropoff_at <= trips.pickup_at, false)
            as dq_fail_non_positive_duration,

        coalesce(
            trips.dropoff_at - trips.pickup_at > to_hours({{ var('max_trip_duration_hours') }}),
            false
        )
            as dq_fail_excessive_duration,

        coalesce(
            trips.trip_distance_miles < 0
            or trips.trip_distance_miles > {{ var('max_trip_distance_miles') }},
            false
        )
            as dq_fail_invalid_trip_distance,

        coalesce(trips.fare_amount < 0 or trips.total_amount < 0, false)
            as dq_fail_negative_amount,

        -- A missing passenger_count is allowed; zero or implausible counts are not
        coalesce(
            trips.passenger_count <= 0
            or trips.passenger_count > {{ var('max_passenger_count') }},
            false
        )
            as dq_fail_invalid_passenger_count,

        vendors.vendor_id is null
            as dq_fail_unknown_vendor,

        payment_types.payment_type_id is null
            as dq_fail_unknown_payment_type,

        -- A missing rate code is allowed (mapped to 99 = Null/unknown in fct_trips)
        trips.rate_code_id is not null and rate_codes.rate_code_id is null
            as dq_fail_unknown_rate_code,

        pickup_zones.location_id is null
            as dq_fail_unknown_pickup_zone,

        dropoff_zones.location_id is null
            as dq_fail_unknown_dropoff_zone

    from trips
    left join {{ ref('vendors') }} as vendors
        on trips.vendor_id = vendors.vendor_id
    left join {{ ref('payment_types') }} as payment_types
        on trips.payment_type_id = payment_types.payment_type_id
    left join {{ ref('rate_codes') }} as rate_codes
        on trips.rate_code_id = rate_codes.rate_code_id
    left join zones as pickup_zones
        on trips.pickup_location_id = pickup_zones.location_id
    left join zones as dropoff_zones
        on trips.dropoff_location_id = dropoff_zones.location_id

)

select
    *,
    {% for check in checks -%}
    cast(dq_fail_{{ check }} as integer){{ " +" if not loop.last }}
    {% endfor -%}
        as dq_failed_check_count,
    concat_ws(', ',
        {% for check in checks -%}
        case when dq_fail_{{ check }} then '{{ check }}' end{{ "," if not loop.last }}
        {% endfor -%}
    ) as dq_failure_reasons
from flagged
