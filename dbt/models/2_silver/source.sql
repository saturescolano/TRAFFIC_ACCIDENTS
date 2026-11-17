select distinct source_id, source_name
from {{ ref('silver_accidents') }}
where source_name is not null
