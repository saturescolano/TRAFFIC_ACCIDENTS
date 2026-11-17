{# Sin datos meteorológicos no hay observación (weather_id NULL). #}
select distinct
    weather_id, weather_timestamp, airport_code, temperature_f, wind_chill_f,
    humidity_pct, pressure_in, visibility_mi, wind_direction, wind_speed_mph,
    precipitation_in, weather_condition
from {{ ref('silver_accidents') }}
where weather_id is not null
