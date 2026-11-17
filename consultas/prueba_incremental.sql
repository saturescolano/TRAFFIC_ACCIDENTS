-- Prueba del modelo incremental `silver_accidents` (entorno DEV).
-- Idea: insertar un accidente a mano en bronze, lanzar `dbt run` y comprobar
-- que SOLO ese registro entra en silver (y de ahí llega a gold).
-- Ejecuta cada bloque en una hoja de Snowflake; el paso 3 se hace en la terminal.

-- 1. Estado inicial (anota los dos números)
SELECT
    (SELECT COUNT(*) FROM DEV_2_SILVER_DB.TRAFFIC_ACCIDENTS.SILVER_ACCIDENTS) AS silver,
    (SELECT COUNT(*) FROM DEV_3_GOLD_DB.TRAFFIC_ACCIDENTS.FACT_ACCIDENTS)     AS fact;

-- 2. Insertar un accidente nuevo a mano: copia una fila existente con otro ID
INSERT INTO DEV_1_BRONZE_DB.TRAFFIC_ACCIDENTS.RAW_ACCIDENTS_1
SELECT * REPLACE ('A-PRUEBA-1' AS ID)
FROM DEV_1_BRONZE_DB.TRAFFIC_ACCIDENTS.RAW_ACCIDENTS_1
LIMIT 1;

-- 3. En la terminal:   dbt run
--    En el log de silver_accidents debe poner  SUCCESS 1  (solo 1 fila procesada).

-- 4. Comprobar: +1 en silver y en la fact, y el accidente aparece en ambas
SELECT
    (SELECT COUNT(*) FROM DEV_2_SILVER_DB.TRAFFIC_ACCIDENTS.SILVER_ACCIDENTS) AS silver,
    (SELECT COUNT(*) FROM DEV_3_GOLD_DB.TRAFFIC_ACCIDENTS.FACT_ACCIDENTS)     AS fact;

SELECT accident_id, severity, start_time_local
FROM DEV_3_GOLD_DB.TRAFFIC_ACCIDENTS.FACT_ACCIDENTS
JOIN DEV_2_SILVER_DB.TRAFFIC_ACCIDENTS.SILVER_ACCIDENTS USING (accident_id)
WHERE accident_id = 'A-PRUEBA-1';

-- 5. Limpieza: el incremental solo añade, no borra, así que hay que quitarlo
--    de bronze y de silver, y reconstruir gold (en la terminal: dbt run)
DELETE FROM DEV_1_BRONZE_DB.TRAFFIC_ACCIDENTS.RAW_ACCIDENTS_1 WHERE id = 'A-PRUEBA-1';
DELETE FROM DEV_2_SILVER_DB.TRAFFIC_ACCIDENTS.SILVER_ACCIDENTS WHERE accident_id = 'A-PRUEBA-1';
