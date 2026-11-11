-- Falla si algún accidente termina antes de empezar.
select accident_id
from {{ ref('accident') }}
where end_time_local < start_time_local
