-- One row per taxi zone. Used for both pickup and dropoff zones in fct_trips.
-- Geometry comes from the shapefile; where a zone has several polygons,
-- the one with the lowest object_id is kept.

with lookup as (

    select * from {{ ref('stg_taxi_zone_lookup') }}

),

shapes as (

    select
        location_id,
        geometry_geojson,
        row_number() over (partition by location_id order by object_id) as polygon_rank
    from {{ ref('stg_taxi_zones') }}

)

select
    lookup.location_id,
    lookup.zone_name,
    lookup.borough,
    lookup.service_zone,
    lookup.borough in ('EWR', 'Unknown', 'N/A') or lookup.borough is null as is_outside_nyc_or_unknown,
    shapes.geometry_geojson
from lookup
left join shapes
    on lookup.location_id = shapes.location_id
    and shapes.polygon_rank = 1
