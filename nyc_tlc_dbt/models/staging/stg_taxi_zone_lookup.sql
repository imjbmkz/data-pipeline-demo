select
    cast(location_id as integer) as location_id,
    borough,
    zone as zone_name,
    service_zone
from {{ source('nyc_tlc', 'taxi_zone_lookup') }}
