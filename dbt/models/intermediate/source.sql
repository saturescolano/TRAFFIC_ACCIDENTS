select distinct
    {{ dbt_utils.generate_surrogate_key(['source_name']) }} as source_id,
    source_name
from {{ ref('stg_accidents') }}
where source_name is not null
