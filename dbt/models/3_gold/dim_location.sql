{# Grano más grueso que la dirección: estado + condado + ciudad + zip (sin calle). #}
select distinct
    {{ dbt_utils.generate_surrogate_key(['state', 'county', 'city', 'zipcode']) }} as location_key,
    state, county, city, zipcode
from {{ ref('location') }}
