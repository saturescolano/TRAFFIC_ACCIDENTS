{{ config(severity='warn', limit=100) }}
-- Aviso: mismo instante, coordenadas y descripción con distinto ID (~300k en el dataset).
select start_time_local, start_lat, start_lng, description, count(*) as n
from {{ ref('accident') }}
group by 1, 2, 3, 4
having count(*) > 1
