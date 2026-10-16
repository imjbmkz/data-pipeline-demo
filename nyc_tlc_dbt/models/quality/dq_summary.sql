-- How many trips failed each check, per source file.
-- A trip that fails several checks is counted once per check.

with checked as (

    select * from {{ ref('trips_checked') }}

),

totals as (

    select source_file, count(*) as total_trips
    from checked
    group by source_file

),

failed_checks as (

    select
        source_file,
        unnest(string_split(dq_failure_reasons, ', ')) as failed_check
    from checked
    where dq_failed_check_count > 0

),

failures as (

    select
        source_file,
        failed_check,
        count(*) as failed_trips
    from failed_checks
    group by source_file, failed_check

)

select
    failures.source_file,
    failures.failed_check,
    failures.failed_trips,
    totals.total_trips,
    round(100.0 * failures.failed_trips / totals.total_trips, 3) as failed_pct
from failures
join totals using (source_file)
order by failures.source_file, failures.failed_trips desc
