with obs as (
    select distinct
        {{ weather_key() }} as weather_id,
        weather_timestamp, airport_code, temperature_f, wind_chill_f, humidity_pct,
        pressure_in, visibility_mi, wind_direction, wind_speed_mph,
        precipitation_in, weather_condition
    from {{ ref('stg_accidents') }}
)

-- Sin datos meteorológicos no hay observación (weather_id NULL)
select * from obs where weather_id is not null
