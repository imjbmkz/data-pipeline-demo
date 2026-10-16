-- Trips that passed every check, with the same columns as stg_yellow_tripdata
-- (the dq_* columns are dropped).

{%- set staged = ref('stg_yellow_tripdata') %}
{%- set trip_columns = adapter.get_columns_in_relation(staged) if execute else [] %}

select
    {%- for column in trip_columns %}
    {{ adapter.quote(column.name) }}{{ "," if not loop.last }}
    {%- else %}
    *
    {%- endfor %}
from {{ ref('trips_checked') }}
where dq_failed_check_count = 0
