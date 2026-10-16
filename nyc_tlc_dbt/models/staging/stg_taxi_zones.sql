-- Note: the TLC shapefile repeats some LocationIDs (one zone split into
-- several polygons), so location_id is not unique here.
select
    cast(location_id as integer) as location_id,
    cast(object_id as integer)   as object_id,
    zone as zone_name,
    borough,
    shape_length,
    shape_area,
    geometry_geojson,
    crs
from {{ source('nyc_tlc', 'taxi_zones') }}
