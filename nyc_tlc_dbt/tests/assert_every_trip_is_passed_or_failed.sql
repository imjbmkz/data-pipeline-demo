-- Every staged trip must land in exactly one of trips_passed or trips_failed.
with counts as (

    select
        (select count(*) from {{ ref('stg_yellow_tripdata') }}) as staged_trips,
        (select count(*) from {{ ref('trips_passed') }})        as passed_trips,
        (select count(*) from {{ ref('trips_failed') }})        as failed_trips

)

select *
from counts
where staged_trips <> passed_trips + failed_trips
