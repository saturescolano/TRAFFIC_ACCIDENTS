{# dbt por defecto crea <schema_target>_<custom>. Aquí queremos exactamente
   {APP_ENV}_{custom}: DEV_SILVER, PRO_GOLD, etc. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ env_var('APP_ENV', 'DEV') | upper }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
