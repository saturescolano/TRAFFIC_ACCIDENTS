{# Silver plano: deduplica bronze (un accidente aparece una vez por origen),
   tipa con try_to_* y calcula las claves de las entidades. Una fila por
   accidente. Las tablas accident, source, location y weather_observation
   salen de aquí, así las claves se definen en un único sitio.

   INCREMENTAL: el primer build crea la tabla entera; los siguientes solo
   añaden los accidentes nuevos (clave accident_id, estrategia merge). Si
   cambias la lógica de las columnas hay que reconstruir con --full-refresh. #}
{{ config(
    materialized="incremental",
    unique_key="accident_id",
    incremental_strategy="merge",
    on_schema_change="append_new_columns"
) }}
with typed as (
select
    id                                                  as accident_id,
    source                                              as source_name,
    try_to_number(severity)::smallint                   as severity,

    try_to_timestamp(start_time)                        as start_time_local,
    try_to_timestamp(end_time)                          as end_time_local,
    -- El CSV solo trae hora local: UTC se calcula con la zona horaria.
    -- Sin timezone (7.8k filas) queda NULL.
    convert_timezone(timezone, 'UTC', try_to_timestamp(start_time))::timestamp_ntz  as start_time_utc,
    convert_timezone(timezone, 'UTC', try_to_timestamp(end_time))::timestamp_ntz    as end_time_utc,
    timezone,

    try_to_double(start_lat)                            as start_lat,
    try_to_double(start_lng)                            as start_lng,
    try_to_double(end_lat)                              as end_lat,
    try_to_double(end_lng)                              as end_lng,
    try_to_double(distance_mi)                          as distance_mi,
    description,

    street, city, county, state, zipcode,

    airport_code,
    try_to_timestamp(weather_timestamp)                 as weather_timestamp,
    try_to_double(temperature_f)                        as temperature_f,
    try_to_double(wind_chill_f)                         as wind_chill_f,
    try_to_double(humidity_pct)                         as humidity_pct,
    try_to_double(pressure_in)                          as pressure_in,
    try_to_double(visibility_mi)                        as visibility_mi,
    wind_direction,
    try_to_double(wind_speed_mph)                       as wind_speed_mph,
    try_to_double(precipitation_in)                     as precipitation_in,
    weather_condition,

    try_to_boolean(amenity)                             as amenity,
    try_to_boolean(bump)                                as bump,
    try_to_boolean(crossing)                            as crossing,
    try_to_boolean(give_way)                            as give_way,
    try_to_boolean(junction)                            as junction,
    try_to_boolean(no_exit)                             as no_exit,
    try_to_boolean(railway)                             as railway,
    try_to_boolean(roundabout)                          as roundabout,
    try_to_boolean(station)                             as station,
    try_to_boolean(stop)                                as stop,
    try_to_boolean(traffic_calming)                     as traffic_calming,
    try_to_boolean(traffic_signal)                      as traffic_signal,
    try_to_boolean(turning_loop)                        as turning_loop,

    sunrise_sunset, civil_twilight, nautical_twilight, astronomical_twilight
from {{ deduplicate(ref('bronze_accidents'), ['id'], ['origin']) }} as bronze
{% if is_incremental() %}
-- Solo accidentes que aún no están en silver (p. ej. un registro insertado a mano en bronze)
where not exists (select 1 from {{ this }} s where s.accident_id = bronze.id)
{% endif %}
)

select
    accident_id,
    {{ dbt_utils.generate_surrogate_key(['source_name']) }}  as source_id,
    {{ dbt_utils.generate_surrogate_key(['street', 'city', 'county', 'state', 'zipcode']) }} as location_id,
    -- Sin ningún dato meteorológico no hay observación: weather_id NULL, no
    -- una observación fantasma compartida por miles de accidentes.
    case
        when weather_timestamp is null and airport_code is null
         and temperature_f is null and wind_chill_f is null and humidity_pct is null
         and pressure_in is null and visibility_mi is null and wind_direction is null
         and wind_speed_mph is null and precipitation_in is null and weather_condition is null
        then null
        else {{ dbt_utils.generate_surrogate_key([
            'weather_timestamp', 'airport_code', 'temperature_f', 'wind_chill_f',
            'humidity_pct', 'pressure_in', 'visibility_mi', 'wind_direction',
            'wind_speed_mph', 'precipitation_in', 'weather_condition'
        ]) }}
    end                                                      as weather_id,
    * exclude (accident_id)
from typed
