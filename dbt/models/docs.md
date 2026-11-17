{# Doc blocks reutilizables. Se referencian desde los .yml con
   description: '{{ doc("nombre") }}'. Las columnas que viajan por varias capas
   (bronze -> silver -> gold) se documentan una sola vez aquí. #}

{% docs __overview__ %}

# TRAFFIC_ACCIDENTS

Pipeline ELT sobre el dataset público **US Accidents (marzo 2023)**:
~7,7 millones de accidentes de tráfico en EE. UU. (2016-2023), cargados en
Snowflake y modelados con dbt en arquitectura medallón.

| Capa | Base de datos (esquema `TRAFFIC_ACCIDENTS`) | Carpeta | Contenido |
|---|---|---|---|
| Bronze | `DEV_1_BRONZE_DB` / `PRO_1_BRONZE_DB` | `1_bronze/` | Dos orígenes crudos (`raw_accidents_1/2`, todo `VARCHAR`) unidos con `UNION ALL` en `bronze_accidents`. Los carga `scripts/load_bronze.py`. |
| Silver | `DEV_2_SILVER_DB` / `PRO_2_SILVER_DB` | `2_silver/` | Deduplicado (macro `deduplicate`), tipado y normalizado a 3FN. |
| Gold | `DEV_3_GOLD_DB` / `PRO_3_GOLD_DB` | `3_gold/` | Modelo dimensional (estrella) para análisis. |

**Entornos.** `APP_ENV=DEV` trabaja con una muestra determinista del 10 % del
CSV; `APP_ENV=PRO` con el archivo completo. Cada entorno tiene sus propias
bases de datos y variables `DEV_*` / `PRO_*`.

**Calidad de datos.** Los tests están declarados en los `.yml` de cada carpeta
(unicidad, no nulos, integridad referencial, valores admitidos, rangos) y en
`tests/` (reglas de negocio). Consulta la sección *Tests* del README para la
lista completa.

{% enddocs %}


{# ───────────────────────── Identificadores y claves ───────────────────────── #}

{% docs accident_id %}
Identificador del accidente tal como viene en el CSV original (columna `ID`,
formato `A-1234567`). Clave natural; única en el dataset.
{% enddocs %}

{% docs source_name %}
Nombre de la fuente que reportó el accidente (en el dataset original, la API
de tráfico origen: p. ej. `Source1`, `Source2`, `Source3`).
{% enddocs %}


{# ───────────────────────── Gravedad y duración ───────────────────────── #}

{% docs severity %}
Gravedad del accidente según su **impacto en el tráfico** (no en las
personas): `1` = poco impacto (retraso corto) … `4` = gran impacto (retraso
largo). Valores admitidos: 1, 2, 3, 4. Es `NULL` si el valor original no se
puede convertir a número.
{% enddocs %}

{% docs distance_mi %}
Longitud del tramo de carretera afectado por el accidente, en **millas**.
{% enddocs %}

{% docs description %}
Descripción en texto libre del accidente tal como la aportó la fuente.
{% enddocs %}


{# ───────────────────────── Tiempo ───────────────────────── #}

{% docs start_time_local %}
Momento de inicio del accidente en **hora local** de la zona donde ocurrió
(el CSV solo trae hora local, sin zona). `NULL` si no se pudo interpretar.
{% enddocs %}

{% docs end_time_local %}
Momento en que se estimó que el impacto en el tráfico terminó, en **hora
local**. `NULL` si no se pudo interpretar. Regla: nunca es anterior a
`start_time_local` (test `assert_end_after_start`).
{% enddocs %}

{% docs start_time_utc %}
`start_time_local` convertido a **UTC** usando `timezone`. Es `NULL` cuando el
accidente no tiene zona horaria (~7,8 mil filas del dataset completo).
{% enddocs %}

{% docs end_time_utc %}
`end_time_local` convertido a **UTC** usando `timezone`. Es `NULL` cuando el
accidente no tiene zona horaria.
{% enddocs %}

{% docs timezone %}
Zona horaria IANA del accidente (p. ej. `US/Eastern`, `US/Central`,
`US/Mountain`, `US/Pacific`). Se usa para pasar de hora local a UTC.
{% enddocs %}


{# ───────────────────────── Geografía ───────────────────────── #}

{% docs start_lat %}
Latitud (grados decimales, WGS84) del punto donde comienza el accidente.
{% enddocs %}

{% docs start_lng %}
Longitud (grados decimales, WGS84) del punto donde comienza el accidente.
{% enddocs %}

{% docs end_lat %}
Latitud del punto donde termina el accidente. Muchas filas no la informan
(`NULL`).
{% enddocs %}

{% docs end_lng %}
Longitud del punto donde termina el accidente. Muchas filas no la informan
(`NULL`).
{% enddocs %}

{% docs street %}
Nombre de la calle o carretera donde ocurrió el accidente. Puede ser `NULL`.
{% enddocs %}

{% docs city %}
Ciudad donde ocurrió el accidente.
{% enddocs %}

{% docs county %}
Condado donde ocurrió el accidente.
{% enddocs %}

{% docs state %}
Estado de EE. UU. (código de dos letras, p. ej. `CA`, `TX`).
{% enddocs %}

{% docs zipcode %}
Código postal (ZIP) del accidente, como texto. Puede venir con ZIP+4
(`12345-6789`) o ser `NULL`.
{% enddocs %}


{# ───────────────────────── Meteorología ───────────────────────── #}

{% docs airport_code %}
Código de la estación meteorológica de aeropuerto (ICAO, p. ej. `KJFK`) más
cercana, de donde provienen las medidas del tiempo.
{% enddocs %}

{% docs weather_timestamp %}
Momento (hora local) en que se registró la observación meteorológica.
{% enddocs %}

{% docs temperature_f %}
Temperatura en grados **Fahrenheit**.
{% enddocs %}

{% docs wind_chill_f %}
Sensación térmica por viento, en grados **Fahrenheit**.
{% enddocs %}

{% docs humidity_pct %}
Humedad relativa, en **porcentaje** (0-100).
{% enddocs %}

{% docs pressure_in %}
Presión atmosférica, en **pulgadas de mercurio** (inHg).
{% enddocs %}

{% docs visibility_mi %}
Visibilidad, en **millas**.
{% enddocs %}

{% docs wind_direction %}
Dirección del viento (texto: `N`, `SW`, `Calm`, `Variable`…).
{% enddocs %}

{% docs wind_speed_mph %}
Velocidad del viento, en **millas por hora**.
{% enddocs %}

{% docs precipitation_in %}
Precipitación acumulada, en **pulgadas**.
{% enddocs %}

{% docs weather_condition %}
Condición meteorológica en texto (p. ej. `Clear`, `Rain`, `Fog`, `Snow`).
{% enddocs %}


{# ───────────────────────── Indicadores de la vía (booleanos) ───────────────────────── #}

{% docs flag_amenity %}
`TRUE` si hay un servicio (amenity) cerca del punto del accidente.
{% enddocs %}

{% docs flag_bump %}
`TRUE` si hay un resalto o badén (speed bump/hump) cerca.
{% enddocs %}

{% docs flag_crossing %}
`TRUE` si hay un paso de peatones cerca.
{% enddocs %}

{% docs flag_give_way %}
`TRUE` si hay una señal de ceda el paso cerca.
{% enddocs %}

{% docs flag_junction %}
`TRUE` si hay un cruce, intersección o enlace cerca.
{% enddocs %}

{% docs flag_no_exit %}
`TRUE` si hay una señal de vía sin salida cerca.
{% enddocs %}

{% docs flag_railway %}
`TRUE` si hay un paso a nivel o vía de tren cerca.
{% enddocs %}

{% docs flag_roundabout %}
`TRUE` si hay una rotonda cerca.
{% enddocs %}

{% docs flag_station %}
`TRUE` si hay una estación (tren, metro, autobús) cerca.
{% enddocs %}

{% docs flag_stop %}
`TRUE` si hay una señal de stop cerca.
{% enddocs %}

{% docs flag_traffic_calming %}
`TRUE` si hay medidas de calmado de tráfico cerca.
{% enddocs %}

{% docs flag_traffic_signal %}
`TRUE` si hay un semáforo cerca.
{% enddocs %}

{% docs flag_turning_loop %}
`TRUE` si hay un lazo de giro (turning loop) cerca.
{% enddocs %}


{# ───────────────────────── Luz natural ───────────────────────── #}

{% docs sunrise_sunset %}
Periodo del día según la posición del sol: `Day` o `Night`.
{% enddocs %}

{% docs civil_twilight %}
Periodo del día según el crepúsculo **civil**: `Day` o `Night`.
{% enddocs %}

{% docs nautical_twilight %}
Periodo del día según el crepúsculo **náutico**: `Day` o `Night`.
{% enddocs %}

{% docs astronomical_twilight %}
Periodo del día según el crepúsculo **astronómico**: `Day` o `Night`.
{% enddocs %}
