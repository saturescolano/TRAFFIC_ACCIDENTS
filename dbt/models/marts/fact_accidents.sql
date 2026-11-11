{# Grano: un accidente. Medidas meteorológicas en el hecho (no en dimensión). #}
select
    {{ dbt_utils.generate_surrogate_key(['a.accident_id']) }}   as accident_key,
    to_number(to_char(a.start_time_local, 'YYYYMMDD'))          as start_date_key,
    to_number(to_char(a.end_time_local, 'YYYYMMDD'))            as end_date_key,
    a.source_id                                                 as source_key,
    {{ dbt_utils.generate_surrogate_key(['a.state', 'a.county', 'a.city', 'a.zipcode']) }} as location_key,

    a.accident_id,
    a.severity,
    a.distance_mi,
    case when a.end_time_utc >= a.start_time_utc
         then datediff('second', a.start_time_utc, a.end_time_utc) / 60.0
    end                                                         as duration_minutes,
    a.start_time_utc,

    w.temperature_f, w.wind_chill_f, w.humidity_pct, w.pressure_in,
    w.visibility_mi, w.wind_speed_mph, w.precipitation_in,
    w.weather_condition,

    a.amenity, a.bump, a.crossing, a.give_way, a.junction, a.no_exit,
    a.railway, a.roundabout, a.station, a.stop, a.traffic_calming,
    a.traffic_signal, a.turning_loop
from (
    select a.*, l.state, l.county, l.city, l.zipcode
    from {{ ref('accident') }} a
    join {{ ref('location') }} l using (location_id)
) a
left join {{ ref('weather_observation') }} w using (weather_id)
