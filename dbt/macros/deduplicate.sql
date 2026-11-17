{# Deduplica una relación: deja una fila por combinación de `partition_by`,
   la primera según `order_by`. Devuelve una subconsulta, así que se usa
   directamente en un FROM:

     from {{ deduplicate(ref('bronze_accidents'), ['id'], ['origin']) }}

   `order_by` decide qué copia sobrevive (p. ej. el origen preferido).
   Usa QUALIFY de Snowflake: no hace falta una CTE intermedia. #}
{% macro deduplicate(relation, partition_by, order_by) %}
(
    select *
    from {{ relation }}
    qualify row_number() over (
        partition by {{ partition_by | join(', ') }}
        order by {{ order_by | join(', ') }}
    ) = 1
)
{% endmacro %}
