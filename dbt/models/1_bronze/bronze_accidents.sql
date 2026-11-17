{# Une los dos orígenes crudos sin tocar los datos. Los accidentes presentes
   en ambos orígenes aparecen DOS veces: deduplicar es trabajo de silver.
   `origin` indica de qué tabla viene cada fila. #}
select 'origin_1' as origin, * from {{ source('raw', 'raw_accidents_1') }}
union all
select 'origin_2' as origin, * from {{ source('raw', 'raw_accidents_2') }}
