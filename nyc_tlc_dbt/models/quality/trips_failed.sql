-- Quarantined trips that failed at least one check.
-- dq_failure_reasons lists every check the trip failed, e.g. 'negative_amount, unknown_vendor'.
select *
from {{ ref('trips_checked') }}
where dq_failed_check_count > 0
