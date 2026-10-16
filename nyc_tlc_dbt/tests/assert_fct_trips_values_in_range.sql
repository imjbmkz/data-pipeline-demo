-- Facts must only hold trips with a positive duration and non-negative distance and amounts.
select *
from {{ ref('fct_trips') }}
where trip_duration_minutes <= 0
   or trip_distance_miles < 0
   or fare_amount < 0
   or total_amount < 0
