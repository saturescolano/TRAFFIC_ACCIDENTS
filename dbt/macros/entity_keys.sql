{# Claves sustitutas deterministas. Si cambias las columnas, hay que
   reconstruir intermediate y marts con --full-refresh. #}

{% macro location_key() %}
    {{ dbt_utils.generate_surrogate_key(['street', 'city', 'county', 'state', 'zipcode']) }}
{% endmacro %}

{# Observación meteorológica sin ningún dato -> sin clave (NULL), no una
   observación fantasma compartida por 22k accidentes. #}
{% macro weather_key() %}
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
    end
{% endmacro %}
