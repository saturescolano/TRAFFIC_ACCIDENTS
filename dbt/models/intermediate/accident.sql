{# Tabla central 3FN. Grano: un accidente. Timezone y los 13 indicadores de
   vía se quedan aquí (v1): timezone tiene 4 valores y los indicadores
   como N:N serían ~100M filas. #}
select
    accident_id,
    {{ dbt_utils.generate_surrogate_key(['source_name']) }} as source_id,
    {{ location_key() }}                                   as location_id,
    {{ weather_key() }}                                    as weather_id,

    start_time_local, end_time_local, start_time_utc, end_time_utc, timezone,
    severity, description, distance_mi,
    start_lat, start_lng, end_lat, end_lng,

    amenity, bump, crossing, give_way, junction, no_exit, railway,
    roundabout, station, stop, traffic_calming, traffic_signal, turning_loop,
    sunrise_sunset, civil_twilight, nautical_twilight, astronomical_twilight
from {{ ref('stg_accidents') }}
