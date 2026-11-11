-- Consultas de análisis sobre el modelo en estrella (capa gold).
-- Se ejecutan en una hoja (worksheet) de Snowflake.
--
-- Entorno: cambia DEV por PRO en la línea siguiente para usar el dataset completo.
--   DEV = muestra determinista del 10 % (~773 mil accidentes)
--   PRO = dataset completo (~7,7 M de accidentes)
USE SCHEMA TRAFFIC_ACCIDENTS_DB.DEV_GOLD;

-- ─────────────────────────────────────────────────────────────
-- 1. Volumen total y rango de fechas
-- ─────────────────────────────────────────────────────────────
SELECT COUNT(*)                  AS accidentes,
       MIN(d.full_date)          AS primera_fecha,
       MAX(d.full_date)          AS ultima_fecha
FROM fact_accidents f
JOIN dim_date d ON d.date_key = f.start_date_key;

-- ─────────────────────────────────────────────────────────────
-- 2. Accidentes por gravedad (1 = poco impacto, 4 = mucho impacto)
-- ─────────────────────────────────────────────────────────────
SELECT severity,
       COUNT(*)                                          AS accidentes,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
FROM fact_accidents
GROUP BY severity
ORDER BY severity;

-- ─────────────────────────────────────────────────────────────
-- 3. Evolución anual
-- ─────────────────────────────────────────────────────────────
SELECT d.year                AS anio,
       COUNT(*)              AS accidentes,
       ROUND(AVG(f.severity), 2) AS gravedad_media
FROM fact_accidents f
JOIN dim_date d ON d.date_key = f.start_date_key
GROUP BY d.year
ORDER BY d.year;

-- ─────────────────────────────────────────────────────────────
-- 4. Top 10 estados por número de accidentes
-- ─────────────────────────────────────────────────────────────
SELECT l.state,
       COUNT(*)                  AS accidentes,
       ROUND(AVG(f.severity), 2) AS gravedad_media
FROM fact_accidents f
JOIN dim_location l ON l.location_key = f.location_key
GROUP BY l.state
ORDER BY accidentes DESC
LIMIT 10;

-- ─────────────────────────────────────────────────────────────
-- 5. Top 10 ciudades
-- ─────────────────────────────────────────────────────────────
SELECT l.city, l.state, COUNT(*) AS accidentes
FROM fact_accidents f
JOIN dim_location l ON l.location_key = f.location_key
GROUP BY l.city, l.state
ORDER BY accidentes DESC
LIMIT 10;

-- ─────────────────────────────────────────────────────────────
-- 6. Laborable frente a fin de semana (accidentes medios por día)
-- ─────────────────────────────────────────────────────────────
SELECT IFF(d.weekend_flag, 'Fin de semana', 'Laborable') AS tipo_dia,
       COUNT(*)                                          AS accidentes,
       COUNT(DISTINCT d.date_key)                        AS dias,
       ROUND(COUNT(*) / COUNT(DISTINCT d.date_key), 1)   AS accidentes_por_dia
FROM fact_accidents f
JOIN dim_date d ON d.date_key = f.start_date_key
GROUP BY tipo_dia;

-- ─────────────────────────────────────────────────────────────
-- 7. Duración media del impacto por gravedad (minutos)
-- ─────────────────────────────────────────────────────────────
SELECT severity,
       ROUND(AVG(duration_minutes), 1)                   AS duracion_media_min,
       ROUND(MEDIAN(duration_minutes), 1)                AS duracion_mediana_min
FROM fact_accidents
WHERE duration_minutes IS NOT NULL
GROUP BY severity
ORDER BY severity;

-- ─────────────────────────────────────────────────────────────
-- 8. Condiciones meteorológicas más frecuentes y su gravedad media
-- ─────────────────────────────────────────────────────────────
SELECT weather_condition,
       COUNT(*)                  AS accidentes,
       ROUND(AVG(severity), 2)   AS gravedad_media
FROM fact_accidents
WHERE weather_condition IS NOT NULL
GROUP BY weather_condition
ORDER BY accidentes DESC
LIMIT 10;

-- ─────────────────────────────────────────────────────────────
-- 9. Gravedad media según la visibilidad
-- ─────────────────────────────────────────────────────────────
SELECT CASE WHEN visibility_mi < 1  THEN '1) < 1 milla'
            WHEN visibility_mi < 5  THEN '2) 1-5 millas'
            WHEN visibility_mi < 10 THEN '3) 5-10 millas'
            ELSE                         '4) >= 10 millas' END AS visibilidad,
       COUNT(*)                AS accidentes,
       ROUND(AVG(severity), 2) AS gravedad_media
FROM fact_accidents
WHERE visibility_mi IS NOT NULL
GROUP BY visibilidad
ORDER BY visibilidad;

-- ─────────────────────────────────────────────────────────────
-- 10. Elementos de la vía presentes cerca del accidente
-- ─────────────────────────────────────────────────────────────
SELECT elemento,
       COUNT_IF(presente)                          AS accidentes,
       ROUND(100 * COUNT_IF(presente) / COUNT(*), 1) AS pct_del_total
FROM fact_accidents
UNPIVOT (presente FOR elemento IN (
    junction, crossing, traffic_signal, stop, railway, roundabout,
    give_way, station, amenity, bump, no_exit, traffic_calming, turning_loop))
GROUP BY elemento
ORDER BY accidentes DESC;

-- ─────────────────────────────────────────────────────────────
-- 11. Calidad de datos: nulos en las columnas clave de la fact
-- ─────────────────────────────────────────────────────────────
SELECT COUNT(*)                                  AS filas,
       COUNT_IF(duration_minutes IS NULL)        AS sin_duracion,
       COUNT_IF(temperature_f IS NULL)           AS sin_temperatura,
       COUNT_IF(visibility_mi IS NULL)           AS sin_visibilidad,
       COUNT_IF(weather_condition IS NULL)       AS sin_condicion_meteo
FROM fact_accidents;
