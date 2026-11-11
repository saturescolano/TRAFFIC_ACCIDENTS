{# Entidad "dirección": calle + ciudad + condado + estado + zip.
   No es un punto geográfico: dos sitios distintos con la misma dirección se
   funden. Filas con calle/zip nulos se agrupan por los campos presentes. #}
select distinct
    {{ location_key() }} as location_id,
    street, city, county, state, zipcode
from {{ ref('stg_accidents') }}
