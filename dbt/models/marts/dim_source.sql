select source_id as source_key, source_name
from {{ ref('source') }}
