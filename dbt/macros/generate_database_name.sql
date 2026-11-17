{# Base de datos = {ENTORNO}_{N}_{CAPA}_DB, p. ej. DEV_2_SILVER_DB, PRO_3_GOLD_DB (el número fija el orden alfabético: DEV arriba, PRO abajo).
   El entorno sale del target de dbt (dev | pro, que sigue a APP_ENV) y la
   capa de `+database:` en dbt_project.yml (1_bronze | 2_silver | 3_gold). #}
{% macro generate_database_name(custom_database_name, node) -%}
    {%- if custom_database_name is none -%}
        {{ target.database }}
    {%- else -%}
        {{ target.name | upper }}_{{ custom_database_name | trim | upper }}_DB
    {%- endif -%}
{%- endmacro %}
