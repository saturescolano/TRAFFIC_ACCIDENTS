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
- Todo reproducible desde el repositorio: `git clone` → `.env` → `dbt build`.

---

## Arquitectura medallón

```
CSV ──load_bronze.py──▶ BRONZE ──────▶ SILVER ──────────────▶ GOLD
                        dato crudo     tipado + 3FN           estrella
                        todo VARCHAR   staging, accident,     fact_accidents
                                       source, location,      dim_date, dim_source,
                                       weather_observation    dim_location
```

| Capa | Para qué sirve |
|---|---|
| **Bronze** | Guarda el dato tal cual llega; se puede reprocesar sin recargar |
| **Silver** | Limpia, tipa y normaliza |
| **Gold** | Modelo dimensional para análisis |

---

## Dos entornos: DEV y PRO

| | DEV | PRO |
|---|---|---|
| Datos | Muestra determinista del **10 %** (773 mil filas) | Dataset **completo** (7,7 M) |
| Esquemas | `DEV_BRONZE / SILVER / GOLD` | `PRO_BRONZE / SILVER / GOLD` |
| Estado | Construido y testeado | Bronze cargado; **sin materializar aún** |

- Un solo cambio de variable (`APP_ENV`) cambia de entorno.
- La muestra se elige por **hash del ID**: siempre es la misma y es un subconjunto exacto del original → resultados reproducibles.
- La carga es **idempotente** (`TRUNCATE` + `COPY INTO`) y pide confirmación en PRO.

---

## Carga a bronze

- Script Python con el conector de Snowflake: `PUT` al stage + `COPY INTO`.
- **Todo como `VARCHAR`**: el tipado se hace después, en dbt.
- Problema real resuelto: algunas descripciones terminan en `\`, y Snowflake lo interpretaba como escape de la coma siguiente y rompía la fila → se desactiva el escape en el formato de archivo.
- Los nombres de columna se normalizan (`Distance(mi)` → `DISTANCE_MI`).

---

## Silver: de dato crudo a 3FN

**Staging** (`stg_accidents`): tipado con `try_to_*` → un dato malo pasa a `NULL` en vez de romper la carga. Calcula la hora **UTC** a partir de la zona horaria.

**Intermediate** (tabla central + 3 entidades):

| Modelo | Grano |
|---|---|
| `accident` | un accidente |
| `source` | una fuente |
| `location` | una dirección (calle + ciudad + condado + estado + zip) |
| `weather_observation` | una combinación de datos meteorológicos |

Claves sustitutas deterministas con `dbt_utils.generate_surrogate_key`.

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
- 773.211 filas en DEV: **mismas filas que `accident`** → el modelo no pierde ni duplica.

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
| **Bronze todo `VARCHAR`, tipado en staging con `try_to_*`** | Un dato mal formado pasa a NULL en vez de romper la carga, y bronze conserva el original |
| **Duplicados: marcar, no borrar** | Mismo instante, coordenadas y descripción, pero distinto ID y a veces distinta gravedad u hora de fin: no es seguro que sean copias |

---

## Materialización: ¿por qué tablas y no vistas?

| Capa | Materialización | Motivo |
|---|---|---|
| **Staging** | **Tabla** | Alimenta 4 modelos (`accident`, `location`, `source`, `weather_observation`). Como vista, el tipado de 7,7 M de filas se repetiría 4 veces por build |
| **Intermediate** | **Tabla** | Los marts hacen JOIN sobre ellas; evita recalcular los `DISTINCT` y los hashes |
| **Marts (gold)** | **Tabla** | Es lo que consultan los usuarios: debe responder rápido y no depender de cálculo en cada consulta |

- Compromiso: las tablas ocupan almacenamiento y se **reconstruyen enteras** en cada build. Aquí compensa: el dato no cambia y se lee muchas más veces de las que se construye.
- Está parametrizado (`DBT_MAT_STAGING`, `DBT_MAT_INTERMEDIATE`, `DBT_MAT_MARTS`): cambiar a vista no requiere tocar código.
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

## ¿Por qué no modelos incrementales?

Un incremental procesa **solo las filas nuevas** desde el último build. Hoy no encaja:

- **No hay filas nuevas:** el dataset es estático.
- **Bronze se recarga entera** con `TRUNCATE`: no hay `loaded_at` ni fecha de corte para saber qué es nuevo.
- **El ahorro es pequeño:** reconstruir 7,7 M de filas es un coste puntual (no medido todavía en PRO).
- **Añade riesgo:** estrategia `merge`, clave única, y si cambias el SQL las filas ya cargadas no se recalculan solas (`--full-refresh`).

**Cuándo sí:** cargas periódicas que añaden registros (p. ej. una API cada día). Haría falta `loaded_at` en bronze, carga con `INSERT`/`MERGE` y `stg_accidents` incremental con `merge` por `accident_id`.

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
| Duplicados | Marcar, no borrar | Se confirma con la fuente que son copias |
| Materialización | Tablas en todas las capas | El almacenamiento o el tiempo de build pesan más que el cómputo de consulta |
| SCD2 / snapshots | No | Hay una fuente que actualiza registros |
| Incrementales | No | Hay cargas periódicas que añaden filas |
| Frescura | No | Los datos pasan a venir de una API viva |

---

## Calidad de datos: 86 tests

| Tipo | Ejemplos |
|---|---|
| Unicidad y no nulos | Todas las claves primarias, FK de la fact |
| Integridad referencial | `fact` → dimensiones; `accident` → `source`, `location`, `weather` |
| Valores admitidos | `severity` 1-4, `timezone`, Day/Night |
| Rangos | Temperatura, humedad, presión, visibilidad ≥ 0, duración ≥ 0 |
| Consistencia | `fact_accidents` tiene las mismas filas que `accident` |
| Reglas de negocio | Fin ≥ inicio; coordenadas en EE. UU.; posibles duplicados |

**Resultado en DEV: 76 OK · 10 avisos · 0 errores.**

---

## Los 10 avisos, explicados

No son fallos del pipeline, son **hallazgos de calidad del dato**:

- **Posibles duplicados:** mismo instante, coordenadas y descripción con distinto ID (~300 mil en el dataset completo). No se eliminan porque el ID es distinto.
- **Lecturas de sensor imposibles:** temperatura (4), sensación térmica (2) y presión (2) fuera de rango plausible.

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
- Herramientas nuevas para mí: dbt (modelos, tests, macros, doc blocks), Snowflake (stages, `COPY INTO`, `UNPIVOT`).

---

## Pendiente y próximos pasos

- [ ] Materializar **PRO** (`dbt build` con el dataset completo).
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
