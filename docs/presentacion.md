---
marp: true
theme: default
paginate: true
title: TRAFFIC_ACCIDENTS — Pipeline ELT con Snowflake y dbt
---

# TRAFFIC_ACCIDENTS
### Pipeline ELT con Snowflake y dbt sobre 7,7 M de accidentes de tráfico

Proyecto de mentorización · Incorporación a Civica Software

<!-- Notas: presentarme en 20 s. Objetivo de hoy: enseñar lo hecho y recoger cambios, no cerrar el proyecto. -->

---

## Qué he construido

- Un **pipeline de datos de extremo a extremo**: del CSV crudo a un modelo analítico listo para consultar.
- Dataset: **US Accidents (marzo 2023)**, ~7,7 M de accidentes en EE. UU. (2016-2023), 46 columnas.
- Stack: **Snowflake** (almacén) + **dbt** (transformación) + **Python** (carga).
- **Seis bases de datos** (`DEV_` / `PRO_` × bronze / silver / gold) y **dos orígenes** de datos con duplicados que se limpian en silver.
- Todo reproducible desde el repositorio: `git clone` → `.env` → `dbt build`.

---

## Arquitectura medallón

```
2 CSV ──load_bronze.py──▶ BRONZE ─────────▶ SILVER ─────────────▶ GOLD
(origen 1 y 2)            raw_1 UNION ALL    deduplica, tipa,      estrella
                          raw_2 (VARCHAR)    3FN: accident,        fact_accidents
                                             source, location,     dim_date, dim_source,
                                             weather_observation   dim_location
```

| Capa | Para qué sirve |
|---|---|
| **Bronze** (`*_1_BRONZE_DB`) | Guarda el dato tal cual llega (dos orígenes unidos con `UNION ALL`, duplicados incluidos); se puede reprocesar sin recargar |
| **Silver** (`*_2_SILVER_DB`) | Deduplica (macro `deduplicate`), tipa y normaliza a 3FN |
| **Gold** (`*_3_GOLD_DB`) | Modelo dimensional para análisis |

Carpetas dbt: `1_bronze/`, `2_silver/`, `3_gold/`. Esquema siempre `TRAFFIC_ACCIDENTS`.

---

## Dos entornos: DEV y PRO

| | DEV | PRO |
|---|---|---|
| Origen 1 | Muestra del **10 %** (773 mil filas) | Dataset **completo** (7,7 M) |
| Origen 2 | La misma muestra (duplicado) | La muestra del 10 % |
| Bases de datos (esquema `TRAFFIC_ACCIDENTS`) | `DEV_1_BRONZE_DB / 2_SILVER_DB / 3_GOLD_DB` | `PRO_1_BRONZE_DB / 2_SILVER_DB / 3_GOLD_DB` |
| Estado | Construido y testeado | Construido y testeado |

- Un solo cambio de variable (`APP_ENV`) cambia de entorno: elige el *target* de dbt (`dev` / `pro`), las bases de datos y los CSV (`DEV_CSV_1/2`, `PRO_CSV_1/2`).
- La muestra se elige por **hash del ID**: siempre es la misma y es un subconjunto exacto del original → resultados reproducibles.
- La carga es **idempotente** (`TRUNCATE` + `COPY INTO`) y pide confirmación en PRO.

---

## Carga a bronze

- `setup_snowflake.py` crea las 6 bases de datos, el formato de archivo y el stage (idempotente).
- `load_bronze.py` (conector de Snowflake): `PUT` al stage + `COPY INTO`, **una vez por origen** → `RAW_ACCIDENTS_1` y `RAW_ACCIDENTS_2`.
- **Todo como `VARCHAR`**: el tipado se hace después, en silver.
- El `UNION ALL` de los dos orígenes lo hace dbt (`bronze_accidents`, con columna `origin`); **no deduplica**.
- Problema real resuelto: algunas descripciones terminan en `\`, y Snowflake lo interpretaba como escape de la coma siguiente y rompía la fila → se desactiva el escape en el formato de archivo.
- Los nombres de columna se normalizan (`Distance(mi)` → `DISTANCE_MI`).

---

## Silver: deduplicar, tipar y normalizar a 3FN

**`silver_accidents`**: deduplica el `UNION ALL` de bronze con la macro `deduplicate` (una fila por `id`; gana `origin_1`), tipa con `try_to_*` → un dato malo pasa a `NULL` en vez de romper la carga. Calcula la hora **UTC** a partir de la zona horaria y las claves de las entidades.

**Intermediate** (tabla central + 3 entidades):

| Modelo | Grano |
|---|---|
| `accident` | un accidente |
| `source` | una fuente |
| `location` | una dirección (calle + ciudad + condado + estado + zip) |
| `weather_observation` | una combinación de datos meteorológicos |

Claves sustitutas deterministas con `dbt_utils.generate_surrogate_key`, usado directamente (sin macros propias).

---

## Deduplicación: bronze → silver

```sql
-- macro deduplicate(relation, partition_by, order_by)
select * from <bronze_accidents>
qualify row_number() over (partition by id order by origin) = 1
```

| | Bronze (`UNION ALL`) | Silver (deduplicado) | Repetidos eliminados |
|---|---|---|---|
| **DEV** | 1.546.422 | 773.211 | 773.211 |
| **PRO** | 8.501.605 | 7.728.394 | 773.211 |

- Mismo `id` en los dos orígenes = **la misma fila**: se queda una (la del origen 1).
- En PRO coincide con el tamaño del CSV completo → la deduplicación elimina exactamente los repetidos.
- Distinto de los *posibles duplicados* (mismo instante y lugar con **distinto** ID): esos no se tocan.

---

## Linaje: por qué `silver_accidents` va primero

```
raw_accidents_1 ─┐
                 ├─▶ bronze_accidents ─▶ silver_accidents ─┬─▶ accident ──────┐
raw_accidents_2 ─┘     (UNION ALL)       (dedup + tipado   ├─▶ source ────────┤
                                          + claves)        ├─▶ location ──────┼─▶ gold
                                                           └─▶ weather_obs. ──┘
```

**`silver_accidents`** es el paso previo dentro de silver (el papel que antes hacía `staging`): una tabla plana, una fila por accidente, donde se hace **una sola vez** el trabajo pesado: deduplicar, tipar, calcular la hora UTC y generar las claves.

**`accident`, `source`, `location` y `weather_observation`** son el modelo 3FN: no limpian nada, solo seleccionan sus columnas (`select distinct` en las tres entidades).

| Ventaja | Inconveniente |
|---|---|
| Deduplicar y tipar 7,7 M de filas **una vez**, no cuatro | Las cuatro tablas dependen de una quinta que no es una entidad real: cuello de botella en el grafo |
| Las claves se definen en **un único sitio** (no pueden diferir entre tablas) | |
| Las FK de `accident` siempre apuntan a filas que existen | |

**Alternativa descartada:** que cada tabla lea de bronze y repita dedup, tipado y claves → lógica copiada 4 veces y mucho más cálculo.

---

## Gold: modelo en estrella

```
                  dim_date (inicio)
                        │
  dim_source ──── fact_accidents ──── dim_date (fin)
                        │
                  dim_location
```

- `fact_accidents`: grano **un accidente**. Medidas: gravedad, distancia, duración, meteorología.
- `dim_date` con **dos roles** (fecha de inicio y de fin).
- `dim_location` más gruesa que `location` (sin calle).
- **Mismas filas que `accident`** → el modelo no pierde ni duplica: 773.211 en DEV y 7.728.394 en PRO.

---

## Decisiones de modelado (1/2)

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **13 indicadores de vía dentro de `accident`** | Normalizarlos como N:N serían ~100 M de filas para guardar booleanos | Tabla `accidente ↔ elemento` |
| **Sin «observación meteorológica fantasma»**: `weather_id` NULL | ~22 mil accidentes sin datos del tiempo no deben apuntar a una fila vacía compartida | Una fila «desconocido» |
| **`location` = dirección, no un punto** | La dirección es lo que trae el dato de forma fiable; las coordenadas ya están en el hecho | Una fila por coordenada |
| **Meteorología en el hecho**, no en dimensión | Son medidas continuas (temperatura, presión…): casi nunca se repiten | Dimensión de clima |
| **`dim_location` sin calle** | Grano útil para análisis (estado, ciudad, zip) y menos filas | Bajar a dirección completa |

<!-- Notas: pregunta 1 y 2 de la última diapositiva salen de aquí. -->

---

## Decisiones de modelado (2/2)

| Decisión | Por qué |
|---|---|
| **Claves sustitutas con hash** (`generate_surrogate_key`) | Deterministas: la misma entrada da siempre la misma clave, sin secuencias que mantener |
| **Hora UTC calculada** | El CSV solo trae hora local; se convierte con la zona horaria. Sin zona (~7,8 mil filas) queda NULL en vez de inventarla |
| **`dim_date` con dos roles** | Inicio y fin del accidente apuntan a la misma dimensión de fecha |
| **Bronze todo `VARCHAR`, tipado en silver con `try_to_*`** | Un dato mal formado pasa a NULL en vez de romper la carga, y bronze conserva el original |
| **Mismo ID en dos orígenes: eliminar en silver** | Es la misma fila repetida; bronze la conserva para poder reprocesar |
| **Posibles duplicados (distinto ID): marcar, no borrar** | Mismo instante, coordenadas y descripción, pero distinto ID y a veces distinta gravedad u hora de fin: no es seguro que sean copias |
| **Una base de datos por capa y entorno** | Separa DEV de PRO y permite dar permisos distintos por capa |

---

## Materialización: ¿por qué tablas y no vistas?

| Capa | Materialización | Motivo |
|---|---|---|
| **Bronze** | **Vista** | Solo es el `UNION ALL` de los dos orígenes: no merece duplicar el almacenamiento |
| **Silver** | **Tabla** (`silver_accidents`: incremental) | `silver_accidents` (dedup + tipado) alimenta 4 modelos y los gold hacen JOIN sobre ellas; evita repetir el cálculo |
| **Gold** | **Tabla** | Es lo que consultan los usuarios: debe responder rápido y no depender de cálculo en cada consulta |

- Compromiso: las tablas ocupan almacenamiento y se **reconstruyen enteras** en cada build. Aquí compensa: el dato no cambia y se lee muchas más veces de las que se construye.
- Está parametrizado (`DBT_MAT_BRONZE`, `DBT_MAT_SILVER`, `DBT_MAT_GOLD`): cambiar a vista no requiere tocar código.
- Hoy la variable es **global**, igual en DEV y en PRO.

---

## ¿Por qué no SCD2 ni snapshots?

**SCD2 / `dbt snapshot` guardan la historia de un registro que cambia.** Aquí no hay cambios que guardar:

- El dataset es una **foto cerrada** (marzo 2023): nadie actualiza los registros.
- La carga es **completa** (`TRUNCATE` + `COPY INTO`): no hay versión anterior con la que comparar.
- Las dimensiones no evolucionan: `dim_source` son 3 filas, `dim_location` es geografía y `dim_date` un calendario.
- Un accidente es un **hecho que ocurre una vez**.

> Añadirlo sería complejidad sin utilidad real.

**Cuándo sí:** una fuente viva que actualice la gravedad o la hora de fin de un accidente. Entonces: `dbt snapshot` sobre `accident` con `unique_key = accident_id` y estrategia `check`.

---

## Modelo incremental: `silver_accidents`

Un incremental procesa **solo las filas nuevas** desde el último build. Está aplicado solo donde tiene sentido:

- **`silver_accidents` es incremental** (`merge` por `accident_id`): el primer build crea la tabla; los siguientes añaden solo los accidentes que aún no están (`where not exists`).
- **Prueba hecha en DEV:** inserto un accidente a mano en bronze → `dbt run` procesa **1 fila** (`SUCCESS 1`, no 773 mil) → aparece en silver y en `fact_accidents` (+1 en ambos). Luego se borra.
- Gold y el resto de silver siguen siendo **tablas completas**: se reconstruyen desde `silver_accidents`.

**Límites que conozco:**
- Solo detecta accidentes **nuevos** (ID nuevo), no cambios en uno existente, y nunca borra.
- Si cambia la lógica de las columnas hay que reconstruir con `--full-refresh`.
- Bronze se recarga entera (`TRUNCATE`): para una carga periódica real haría falta `loaded_at` y `INSERT`/`MERGE`.

---

## Decisiones de calidad y de entorno

| Decisión | Por qué |
|---|---|
| **Rangos y duplicados en `warn`, no `error`** | Son hallazgos del dato, no fallos del pipeline: avisan sin bloquear el build |
| **Reglas de negocio en `error`** (fin ≥ inicio, claves, FK) | Si se rompen, el modelo es incorrecto |
| **Sin control de frescura (`source freshness`)** | El dataset es una foto estática, no un feed |
| **DEV = muestra del 10 % por hash del ID** | Reproducible y subconjunto exacto del original; iterar rápido y barato |
| **Un solo cambio (`APP_ENV`) cambia de entorno** | Evita tocar PRO por accidente; la carga a PRO pide confirmación |
| **Carga idempotente** (`TRUNCATE` + `COPY`) | Repetirla no duplica filas |

---

## Resumen: qué decidí y cuándo lo revisaría

| Decisión | Hoy | Lo revisaría si… |
|---|---|---|
| Indicadores de vía | En `accident` | Hay que analizar cada elemento por separado |
| Granularidad de `dim_location` | Sin calle | Se quiere analizar por carretera |
| Duplicados | Mismo ID: eliminar en silver. Distinto ID: marcar, no borrar | Se confirma con la fuente que los posibles duplicados son copias |
| Materialización | Vista en bronze, tablas en silver y gold | El almacenamiento o el tiempo de build pesan más que el cómputo de consulta |
| SCD2 / snapshots | No | Hay una fuente que actualiza registros |
| Incrementales | Solo `silver_accidents` (por ID nuevo) | Hay cargas periódicas con cambios sobre registros existentes (haría falta `loaded_at`) |
| Frescura | No | Los datos pasan a venir de una API viva |

---

## Calidad de datos: 91 tests

| Tipo | Ejemplos |
|---|---|
| Unicidad y no nulos | Todas las claves primarias, FK de la fact |
| Integridad referencial | `fact` → dimensiones; `accident` → `source`, `location`, `weather` |
| Valores admitidos | `severity` 1-4, `timezone`, Day/Night |
| Rangos | Temperatura, humedad, presión, visibilidad ≥ 0, duración ≥ 0 |
| Consistencia | `fact_accidents` tiene las mismas filas que `accident` |
| Reglas de negocio | Fin ≥ inicio; coordenadas en EE. UU.; posibles duplicados |

**Resultado en DEV y en PRO: 81 OK · 10 avisos · 0 errores.**

---

## Los 10 avisos, explicados

No son fallos del pipeline, son **hallazgos de calidad del dato**:

- **Posibles duplicados:** mismo instante, coordenadas y descripción con distinto ID (~300 mil en el dataset completo). No se eliminan porque el ID es distinto.
- **Lecturas de sensor imposibles:** temperatura, sensación térmica y presión fuera de rango plausible (en DEV: 4, 2 y 2 filas; se repiten en silver, `weather_observation` y la fact).

Los rangos son `warn`, no `error`: avisan sin bloquear el build.

---

## Documentación

- Cada modelo y columna tiene **descripción y grano**; las columnas compartidas se escriben una sola vez (*doc blocks*).
- `dbt docs generate` produce un sitio navegable con **linaje** entre modelos y los tests asociados.
- README con arquitectura, puesta en marcha, decisiones y lagunas conocidas.
- Los tests están **documentados también en lo que no cubren**.

---

## Qué dicen los datos (muestra DEV, 773 mil accidentes)

**Gravedad** (1 = poco impacto en el tráfico, 4 = mucho):

| 1 | 2 | 3 | 4 |
|---|---|---|---|
| 0,9 % | **79,6 %** | 16,9 % | 2,7 % |

- **Geografía:** California concentra el 22,5 % (174 mil), seguida de Florida (88 mil) y Texas (58 mil). Ciudades: Miami, Houston, Los Ángeles.
- **Tendencia:** de 41 mil (2016) a 176 mil (2022). Parte del crecimiento es mayor cobertura de las fuentes, no más accidentes reales.
- **Laborables:** 355 accidentes/día frente a 172 en fin de semana (el doble).

---

## Más hallazgos

- **Vía:** el 14,8 % de los accidentes ocurre cerca de un semáforo, el 11,3 % cerca de un paso de peatones y el 7,4 % en un cruce.
- **Duración (mediana):** 45 min en gravedad 1 → **129 min en gravedad 4**.
- **Meteorología:** la mayoría ocurre con buen tiempo (`Fair`, `Mostly Cloudy`, `Clear`).
- **Visibilidad:** la gravedad media apenas cambia (2,21-2,23) entre < 1 milla y ≥ 10 millas.

> La gravedad mide el **impacto en el tráfico**, no el daño a las personas, y por eso no sube con el mal tiempo.

---

## Lo que aprendí y lo que me costó

- **Modelar el grano** de cada tabla antes de escribir SQL evita la mayoría de errores posteriores.
- Los **tests encuentran cosas** que no ves a ojo: 8 lecturas de sensor imposibles y 300 mil posibles duplicados.
- Pasé de «tabla plana» a un modelo **3FN + estrella** y entendí por qué ambos.
- Trabajar con **dos entornos** desde el principio evita tocar el dato completo por accidente.
- Con **dos orígenes** y una macro de deduplicación, el dato repetido se limpia en un único sitio (silver) sin perder el crudo en bronze.
- Menos es más: las macros de claves propias sobraban; `dbt_utils` directamente basta.
- Herramientas nuevas para mí: dbt (modelos, tests, macros, doc blocks), Snowflake (stages, `COPY INTO`, `UNPIVOT`).

---

## Pendiente y próximos pasos

- [x] Materializar **PRO** (`dbt build` con el dataset completo): 7.728.394 accidentes, 91 tests sin errores.
- [ ] Más tests: coherencia `location` ↔ `dim_location`; `accepted_values` en estado y meteorología.
- [ ] Decidir qué hacer con los **posibles duplicados** (filtrar, marcar o dejar).
- [ ] Orquestación (programar la carga y el build) y CI.
- [ ] Capa de consumo: cuadro de mando sobre gold.

---

## Preguntas para vosotros

1. ¿Es razonable mantener los 13 indicadores de vía en `accident`, o lo normalizáis?
2. ¿`dim_location` sin calle es el grano adecuado, o conviene bajar a dirección?
3. ¿Qué hacéis con los posibles duplicados: eliminar, marcar o dejar?
4. ¿Qué os gustaría ver en una siguiente iteración?

**Gracias. Repositorio:** github.com/saturescolano/TRAFFIC_ACCIDENTS
