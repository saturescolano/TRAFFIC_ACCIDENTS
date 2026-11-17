{# El esquema es siempre el mismo (TRAFFIC_ACCIDENTS); lo que cambia entre
   entornos y capas es la BASE DE DATOS (ver generate_database_name). #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}
