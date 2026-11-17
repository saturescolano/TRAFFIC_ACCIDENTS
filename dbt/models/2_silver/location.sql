{# Entidad "dirección": calle + ciudad + condado + estado + zip.
   No es un punto geográfico: dos sitios distintos con la misma dirección se
   funden. #}
select distinct location_id, street, city, county, state, zipcode
from {{ ref('silver_accidents') }}
