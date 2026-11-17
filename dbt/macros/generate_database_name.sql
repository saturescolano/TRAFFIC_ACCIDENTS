{# Base de datos = {ENTORNO}_{CAPA}_DB, p. ej. DEV_SILVER_DB, PRO_GOLD_DB.
   El entorno sale del target de dbt (dev | pro, que sigue a APP_ENV) y la
   capa de `+database:` en dbt_project.yml (bronze | silver | gold). #}
{% macro generate_database_name(custom_database_name, node) -%}
    {%- if custom_database_name is none -%}
        {{ target.database }}
    {%- else -%}
        {{ target.name | upper }}_{{ custom_database_name | trim | upper }}_DB
    {%- endif -%}
{%- endmacro %}
