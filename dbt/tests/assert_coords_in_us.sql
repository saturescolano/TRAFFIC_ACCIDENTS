{{ config(severity='warn') }}
-- Aviso (no error): coordenadas fuera del rango aproximado de EE. UU. (incl. Alaska y Hawái).
select accident_id, start_lat, start_lng
from {{ ref('accident') }}
where start_lat not between 17 and 72
   or start_lng not between -180 and -64
