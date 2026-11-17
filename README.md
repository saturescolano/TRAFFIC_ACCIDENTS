# TRAFFIC_ACCIDENTS

Pipeline ELT sobre el dataset público **US Accidents (marzo 2023)**: ~7,7 millones de accidentes de tráfico en EE. UU. (2016-2023). Los datos se cargan en **Snowflake** y se transforman con **dbt** en una arquitectura medallón (bronze → silver → gold).

Proyecto de mentorización para la incorporación a Civica Software.

## Índice

1. [Arquitectura](#arquitectura)
2. [Estructura del repositorio](#estructura-del-repositorio)
3. [Puesta en marcha](#puesta-en-marcha)
4. [Entornos DEV y PRO](#entornos-dev-y-pro)
5. [Modelos de datos](#modelos-de-datos)
6. [Tests y calidad de datos](#tests-y-calidad-de-datos)
7. [Decisiones de diseño](#decisiones-de-diseño)
8. [Documentación generada con dbt](#documentación-generada-con-dbt)

## Arquitectura

```
2 CSV ──load_bronze.py──▶ BRONZE ───────────────▶ SILVER ───────────────▶ GOLD
(origen 1 y 2)            raw_accidents_1          silver_accidents        (estrella)
                          UNION ALL                (dedup + tipado)        fact_accidents
                          raw_accidents_2          accident, source,       dim_date, dim_source,
                          = bronze_accidents       location,               dim_location
                                                   weather_observation
```

Seis bases de datos, cada una con el esquema `TRAFFIC_ACCIDENTS`:

| Capa | DEV | PRO | Carpeta dbt | Contenido |
|---|---|---|---|---|
| Bronze | `DEV_1_BRONZE_DB` | `PRO_1_BRONZE_DB` | `models/1_bronze/` | Dos orígenes crudos (todo `VARCHAR`) y su `UNION ALL`, con duplicados. Los carga `scripts/load_bronze.py`. |
| Silver | `DEV_2_SILVER_DB` | `PRO_2_SILVER_DB` | `models/2_silver/` | Deduplicado (macro `deduplicate`), tipado y normalizado a 3FN. |
| Gold | `DEV_3_GOLD_DB` | `PRO_3_GOLD_DB` | `models/3_gold/` | Modelo dimensional en estrella para análisis. |

La base de datos de cada modelo la fija la macro `generate_database_name` (`{ENTORNO}_{N}_{CAPA}_DB`) y el esquema `generate_schema_name` (siempre `TRAFFIC_ACCIDENTS`).

## Estructura del repositorio

```
.
├── .env.example              # plantilla de variables de entorno (copiar a .env)
├── requirements.txt          # dependencias Python
├── scripts/
│   ├── setup_snowflake.py    # crea las 6 bases de datos, esquema, CSV_FORMAT y RAW_STAGE
│   ├── load_bronze.py        # carga los 2 orígenes del entorno (TRUNCATE + COPY INTO)
│   ├── sample_csv.py         # genera la muestra determinista para DEV
│   ├── dbt.py                # ejecuta dbt cargando antes el .env
│   └── env.ps1               # prepara la sesión de PowerShell para usar `dbt` a secas
└── dbt/
    ├── dbt_project.yml       # base de datos y materialización por capa
    ├── profiles.yml          # targets dev y pro (solo variables de entorno)
    ├── packages.yml          # dbt_utils >=1.3.0, <2.0.0
    ├── macros/
    │   ├── deduplicate.sql             # una fila por clave (QUALIFY row_number)
    │   ├── generate_database_name.sql  # {ENTORNO}_{N}_{CAPA}_DB
    │   └── generate_schema_name.sql    # siempre TRAFFIC_ACCIDENTS
    ├── models/
    │   ├── docs.md                   # doc blocks reutilizables y página de inicio de dbt docs
    │   ├── 1_bronze/                 # sources, bronze_accidents (UNION ALL)
    │   ├── 2_silver/                 # silver_accidents, accident, source, location, weather_observation
    │   └── 3_gold/                   # fact_accidents, dim_date, dim_source, dim_location
    └── tests/                        # tests singulares (reglas de negocio) + _tests.yml
```

## Puesta en marcha

Requisitos: Python 3.10+, una cuenta de Snowflake con permisos para crear bases de datos (rol `SYSADMIN`) y un warehouse, y el CSV original de US Accidents.

```bash
python -m venv .venv
.venv\Scripts\activate                # Windows
pip install -r requirements.txt

copy .env.example .env                # y rellenar credenciales y rutas de los CSV

python scripts/load_bronze.py --test  # comprueba la conexión
python scripts/setup_snowflake.py     # crea DEV_*_DB y PRO_*_DB (una sola vez)
python scripts/sample_csv.py          # genera la muestra del 10 % (solo la primera vez)
python scripts/load_bronze.py         # carga los 2 orígenes según APP_ENV

cd dbt && ..\.venv\Scripts\dbt deps && cd ..   # instala dbt_utils
python scripts/dbt.py debug           # comprueba la conexión de dbt
python scripts/dbt.py build           # run + test de todos los modelos
```

**Usar `dbt` directamente.** El proyecto dbt vive en la subcarpeta `dbt/`, así que `dbt test` a secas desde la raíz falla con *No dbt_project.yml found*. Para evitarlo, carga una vez por terminal el script de entorno (PowerShell):

```powershell
. .\scripts\env.ps1      # carga el .env y apunta dbt a dbt/ (nota el punto inicial)
dbt test
dbt run --select 3_gold
```

Alternativamente, `scripts/dbt.py` es un envoltorio que carga el `.env` y añade `--project-dir`/`--profiles-dir`: `python scripts/dbt.py run --select 3_gold`.

### Variables de entorno (`.env`)

| Variable | Descripción |
|---|---|
| `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD` | Credenciales (obligatorias). |
| `SNOWFLAKE_ROLE` | Rol (por defecto `SYSADMIN`). |
| `SNOWFLAKE_WAREHOUSE` | Warehouse. `DEV_SNOWFLAKE_WAREHOUSE` / `PRO_SNOWFLAKE_WAREHOUSE` (opcionales) lo sobrescriben por entorno. |
| `APP_ENV` | `DEV` o `PRO`. Decide target de dbt, bases de datos y CSV a cargar. |
| `DEV_CSV_1`, `DEV_CSV_2` | CSV de los dos orígenes de DEV (la muestra, duplicada). |
| `PRO_CSV_1`, `PRO_CSV_2` | CSV de los dos orígenes de PRO (el original completo, duplicado). Si falta `*_CSV_2`, se usa el mismo archivo que `*_CSV_1`. |
| `SAMPLE_PERCENT` | Porcentaje de la muestra (por defecto 10). |
| `DBT_MAT_BRONZE`, `DBT_MAT_SILVER`, `DBT_MAT_GOLD` | Opcionales. Materialización por capa (`table` o `view`; por defecto `view`, `table`, `table`). |

> `.env` y los CSV están en `.gitignore`: nunca se suben al repositorio.

## Entornos DEV y PRO

| | DEV | PRO |
|---|---|---|
| `APP_ENV` / target dbt | `DEV` / `dev` | `PRO` / `pro` |
| CSV cargado (x2 orígenes) | `DEV_CSV_1/2` (muestra 10 %) | `PRO_CSV_1/2` (completo) |
| Bases de datos | `DEV_1_BRONZE_DB`, `DEV_2_SILVER_DB`, `DEV_3_GOLD_DB` | `PRO_1_BRONZE_DB`, `PRO_2_SILVER_DB`, `PRO_3_GOLD_DB` |

- **Muestra determinista.** `sample_csv.py` se queda con las filas cuyo hash del `ID` cae en el porcentaje indicado. Es siempre la misma y un subconjunto exacto del original, así que los resultados de DEV son reproducibles.
- **Carga idempotente.** `load_bronze.py` hace `TRUNCATE` + `COPY INTO` en cada origen: repetirla no duplica filas. En PRO pide confirmación (`--yes` la omite).
- **Duplicados a propósito.** Los dos orígenes contienen el mismo CSV, así que `bronze_accidents` tiene cada accidente dos veces (DEV: 1.546.422 filas) y silver lo deja en una (773.211) con la macro `deduplicate`.

## Modelos de datos

### Bronze
`raw_accidents_1` y `raw_accidents_2`: una fila por línea del CSV, todas las columnas `VARCHAR`, con nombres normalizados (`Distance(mi)` → `DISTANCE_MI`). `bronze_accidents` es su `UNION ALL` con una columna `origin` (`origin_1` / `origin_2`); no deduplica.

### Silver

| Modelo | Grano | Descripción |
|---|---|---|
| `silver_accidents` | un accidente | **Incremental** (`merge` por `accident_id`). Deduplica por `id` (macro `deduplicate`; gana `origin_1`), tipa con `try_to_*` (los inválidos pasan a `NULL`), calcula horas UTC y las claves de las entidades. |
| `accident` | un accidente | Tabla central 3FN con FK a `source`, `location` y `weather_observation`. |
| `source` | una fuente | Fuentes distintas (`source_name`). |
| `location` | una dirección | Calle + ciudad + condado + estado + zip. |
| `weather_observation` | una combinación de datos meteorológicos | Los 11 campos del tiempo. Sin datos no hay observación (`weather_id` NULL). |

### Linaje: por qué `silver_accidents` va primero

```
raw_accidents_1 ─┐
                 ├─▶ bronze_accidents ─▶ silver_accidents ─┬─▶ accident ─────┐
raw_accidents_2 ─┘     (UNION ALL)       (dedup + tipado   ├─▶ source ───────┤
                                          + claves)        ├─▶ location ─────┼─▶ gold
                                                           └─▶ weather_obs. ─┘
```

`silver_accidents` es el paso previo dentro de silver (el papel que antes hacía `staging`): tabla plana, una fila por accidente, donde se deduplica, se tipa, se calcula la hora UTC y se generan las claves **una sola vez**. `accident`, `source`, `location` y `weather_observation` (3FN) no limpian nada: solo seleccionan sus columnas (`select distinct` en las tres entidades).

- **Ventajas:** el trabajo pesado sobre 7,7 M de filas se hace una vez, no cuatro; las claves se definen en un único sitio y no pueden diferir entre tablas; las FK de `accident` siempre apuntan a filas que existen.
- **Inconveniente:** las cuatro tablas dependen de una quinta que no es una entidad real (cuello de botella en el grafo de linaje).
- **Alternativa descartada:** que cada tabla lea de bronze y repita dedup, tipado y claves: lógica copiada cuatro veces y mucho más cálculo.

Para verlo: `python scripts/dbt.py docs generate` y `python scripts/dbt.py docs serve`, y abrir un modelo → botón *Lineage* (en http://localhost:8080).

### Gold (estrella)

```
                dim_date (rol inicio)
                      │
dim_source ── fact_accidents ── dim_date (rol fin)
                      │
                dim_location
```

| Modelo | Grano | Descripción |
|---|---|---|
| `fact_accidents` | un accidente | Medidas: `severity`, `distance_mi`, `duration_minutes` y meteorología. Incluye los 13 indicadores de vía. |
| `dim_date` | un día natural | Solo días que aparecen como inicio o fin de algún accidente. `weekday` es ISO (1 = lunes … 7 = domingo). |
| `dim_source` | una fuente | Copia de `source` con la clave renombrada. |
| `dim_location` | estado + condado + ciudad + zip | Más gruesa que `location` (sin calle). |

### Claves

Todas las claves sustitutas son hashes MD5 deterministas generados directamente con `dbt_utils.generate_surrogate_key` (sin macros propias), salvo `date_key`, que es el entero `YYYYMMDD`.

| Clave | Se calcula a partir de |
|---|---|
| `source_id` / `source_key` | `source_name` |
| `location_id` | calle, ciudad, condado, estado, zip |
| `location_key` (gold) | estado, condado, ciudad, zip |
| `weather_id` | los 11 campos meteorológicos (NULL si todos son nulos) |
| `accident_key` | `accident_id` |
| `date_key` | fecha como `YYYYMMDD` |

La documentación completa columna a columna está en los `.yml` de cada carpeta y en [dbt/models/docs.md](dbt/models/docs.md).

## Tests y calidad de datos

Se ejecutan con `python scripts/dbt.py test` (o `build`, que ejecuta modelos y tests en orden de dependencia).

Resultado actual en DEV (muestra del 10 %): **91 tests, 81 pasan, 10 avisan (`warn`), 0 fallan.**

Todos los tests genéricos usan la sintaxis con `arguments:` de dbt ≥ 1.10.

### 1. Unicidad y no nulos (`unique`, `not_null`)

| Modelo | Columna | Tests |
|---|---|---|
| `raw_accidents_1` / `raw_accidents_2` (fuentes) | `id` | `unique`, `not_null` (único por origen) |
| `bronze_accidents` | `id`, `origin` | `not_null` (`id` se repite por origen) |
| `silver_accidents` | `accident_id` | `unique`, `not_null` |
| `silver_accidents` | `severity`, `start_time_local`, `start_lat`, `start_lng` | `not_null` |
| `accident` | `accident_id` | `unique`, `not_null` |
| `accident` | `source_id`, `location_id`, `severity`, `start_time_local`, `start_lat`, `start_lng` | `not_null` |
| `source` / `location` / `weather_observation` | `source_id` / `location_id` / `weather_id` | `unique`, `not_null` |
| `fact_accidents` | `accident_key` | `unique`, `not_null` |
| `fact_accidents` | `start_date_key`, `source_key`, `location_key`, `severity` | `not_null` |
| `dim_date` / `dim_source` / `dim_location` | `date_key` / `source_key` / `location_key` | `unique`, `not_null` |
| `dim_date` | `weekend_flag` | `not_null` |

### 2. Integridad referencial (`relationships`)

| Hijo | Columna | Padre | Notas |
|---|---|---|---|
| `accident` | `source_id` | `source.source_id` | |
| `accident` | `location_id` | `location.location_id` | |
| `accident` | `weather_id` | `weather_observation.weather_id` | Solo filas con `weather_id is not null`. |
| `fact_accidents` | `start_date_key` | `dim_date.date_key` | |
| `fact_accidents` | `end_date_key` | `dim_date.date_key` | |
| `fact_accidents` | `source_key` | `dim_source.source_key` | |
| `fact_accidents` | `location_key` | `dim_location.location_key` | |

### 3. Valores admitidos (`accepted_values`)

Se aplican en `silver_accidents` y, para `severity` y `timezone`, también en `accident`. Las columnas que admiten `NULL` se comprueban solo cuando tienen valor (`where ... is not null`).

| Columna | Valores | Modelos |
|---|---|---|
| `severity` | 1, 2, 3, 4 | `silver_accidents`, `accident`, `fact_accidents` |
| `timezone` | `US/Eastern`, `US/Central`, `US/Mountain`, `US/Pacific` | `silver_accidents`, `accident` |
| `sunrise_sunset`, `civil_twilight`, `nautical_twilight`, `astronomical_twilight` | `Day`, `Night` | `silver_accidents`, `accident` |

### 4. Rangos numéricos (`dbt_utils.accepted_range`)

Los límites son rangos físicos plausibles. Todos tienen severidad `warn`: un valor atípico avisa pero no bloquea el build.

| Columna | Rango | Modelos |
|---|---|---|
| `temperature_f`, `wind_chill_f` | −100 a 140 | `silver_accidents`, `weather_observation`, `fact_accidents` |
| `humidity_pct` | 0 a 100 | ídem |
| `pressure_in` | 0 a 40 | ídem |
| `visibility_mi`, `wind_speed_mph`, `precipitation_in` | ≥ 0 | ídem |
| `distance_mi` | ≥ 0 | `fact_accidents` |
| `duration_minutes` | ≥ 0 | `fact_accidents` (severidad `error`) |
| `day`, `month`, `quarter`, `weekday` | 1-31, 1-12, 1-4, 1-7 | `dim_date` |

### 5. Consistencia entre tablas

| Test | Modelo | Qué comprueba |
|---|---|---|
| `dbt_utils.equal_rowcount` | `fact_accidents` | Tiene exactamente las mismas filas que `accident` (el JOIN con `location` y `weather_observation` no pierde ni duplica accidentes). |

### 6. Tests singulares (reglas de negocio, en `dbt/tests/`)

| Test | Severidad | Qué comprueba |
|---|---|---|
| `assert_end_after_start` | `error` | Ningún accidente termina antes de empezar. |
| `assert_coords_in_us` | `warn` | Coordenadas dentro del rango aproximado de EE. UU. (lat 17-72, lng -180 a -64, incluye Alaska y Hawái). |
| `assert_possible_duplicates` | `warn` | Mismo instante, coordenadas y descripción con distinto ID (~300 mil en el dataset completo). No se eliminan: el ID es distinto. |

### Avisos conocidos en DEV

Los 10 avisos actuales son reales, no errores del pipeline:

- `assert_possible_duplicates`: devuelve 100 filas (el test tiene `limit 100`).
- Rangos de `temperature_f` (4 valores), `wind_chill_f` (2) y `pressure_in` (2): lecturas de sensor fuera del rango plausible. Se repiten en `silver_accidents`, `weather_observation` y la fact porque el dato se propaga.

### Lagunas conocidas (pendientes)

- **Frescura de la fuente (`source freshness`):** no se define a propósito. El dataset es una foto estática, no un feed que se actualice.
- **`accepted_values` de `state`, `wind_direction` y `weather_condition`:** no se incluyen por tener listas largas y abiertas. Una opción sería `relationships` contra un seed de estados.
- **Coherencia entre `location` y `dim_location`:** no hay un test que compruebe que cada `location_key` de la fact coincide con una dirección de `location` (solo la integridad con `dim_location`).
- **Umbrales de `warn`:** al ser avisos, no hay nada que bloquee un aumento de valores atípicos. Si se quiere, se puede fijar `error_if` con un límite.

## Modelo incremental

`silver_accidents` es incremental: el primer build crea la tabla y los siguientes solo añaden los accidentes cuyo `id` aún no está en silver (`where not exists`, estrategia `merge`). El resto de silver y gold son tablas completas que se reconstruyen desde él.

Para comprobarlo en DEV, [consultas/prueba_incremental.sql](consultas/prueba_incremental.sql): se inserta un accidente a mano en `RAW_ACCIDENTS_1`, `dbt run` procesa **1 fila** (`SUCCESS 1`) y aparece en silver y en `fact_accidents`.

Límites: solo detecta IDs nuevos (no cambios ni borrados) y, si cambia la lógica de las columnas, hay que reconstruir con `dbt run --full-refresh --select silver_accidents`. `DBT_MAT_SILVER` no afecta a este modelo.

## Decisiones de diseño

- **Medallón en tres capas, una base de datos por capa y entorno.** Bronze conserva el dato crudo para poder reprocesar sin volver a cargar; silver deduplica, tipa y normaliza; gold sirve a análisis. Separar por base de datos permite dar permisos distintos por capa y entorno.
- **Dos orígenes y deduplicación en silver.** Bronze no corrige nada (`UNION ALL`); la macro `deduplicate` se aplica al pasar a silver.
- **Bronze todo `VARCHAR`, tipado en silver con `try_to_*`.** Un dato mal formado se convierte en `NULL` en lugar de romper la carga.
- **UTC calculado.** El CSV solo trae hora local; se convierte a UTC con `timezone`. Sin zona horaria (~7,8 mil filas) queda `NULL`.
- **`location` es una dirección, no un punto.** Dos sitios distintos con la misma dirección se funden. `dim_location` es aún más gruesa (sin calle).
- **Sin observación fantasma.** Un accidente sin ningún dato del tiempo tiene `weather_id` NULL, en vez de apuntar a una fila vacía compartida por ~22 mil accidentes.
- **Indicadores de vía en `accident` (v1).** Los 13 booleanos se quedan en la tabla central: normalizarlos como N:N generaría ~100 M de filas. `timezone` (4 valores) también se queda.
- **Meteorología en el hecho.** Las medidas del tiempo van en `fact_accidents`, no en una dimensión.
- **`dim_date` con dos roles.** `fact_accidents` referencia la misma dimensión por `start_date_key` y `end_date_key`.
- **Materialización configurable.** `DBT_MAT_*` permite pasar capas de `table` a `view` sin tocar código (bronze es vista por defecto).

## Documentación generada con dbt

```bash
python scripts/dbt.py docs generate
python scripts/dbt.py docs serve
```

Genera un sitio navegable con descripciones de modelos y columnas, linaje entre modelos y los tests asociados. La página de inicio sale del bloque `__overview__` de [dbt/models/docs.md](dbt/models/docs.md).
