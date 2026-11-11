"""Carga un CSV en la capa bronze de Snowflake según el entorno.

  APP_ENV=DEV -> CSV_SAMPLE   -> TRAFFIC_ACCIDENTS_DB.DEV_BRONZE.RAW_ACCIDENTS
  APP_ENV=PRO -> CSV_ORIGINAL -> TRAFFIC_ACCIDENTS_DB.PRO_BRONZE.RAW_ACCIDENTS

Uso:
  python scripts/load_bronze.py --test          # solo prueba la conexión
  python scripts/load_bronze.py                 # usa APP_ENV del .env
  python scripts/load_bronze.py --env PRO       # fuerza el entorno

Todas las columnas se cargan como VARCHAR (bronze = dato crudo). El tipado
se hace después en la capa staging de dbt. Cada carga hace TRUNCATE + COPY,
así que repetirla no duplica filas.
"""
import argparse
import csv
import os
import re
import sys
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

CSV_BY_ENV = {"DEV": "CSV_SAMPLE", "PRO": "CSV_ORIGINAL"}
TABLE = "RAW_ACCIDENTS"


def clean_column(name: str) -> str:
    """'Distance(mi)' -> DISTANCE_MI, 'Humidity(%)' -> HUMIDITY_PCT."""
    name = name.replace("(%)", "_pct")
    name = re.sub(r"\((\w+)\)", r"_\1", name)
    return re.sub(r"\W+", "_", name).strip("_").upper()


def connect():
    missing = [
        k for k in ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD")
        if not os.getenv(k)
    ]
    if missing:
        sys.exit(f"Faltan variables en el .env: {', '.join(missing)}")
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role=os.getenv("SNOWFLAKE_ROLE", "SYSADMIN"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", choices=["DEV", "PRO"], help="sobrescribe APP_ENV")
    parser.add_argument("--test", action="store_true", help="solo probar la conexión")
    parser.add_argument("--yes", action="store_true", help="no pedir confirmación en PRO")
    args = parser.parse_args()

    env = (args.env or os.getenv("APP_ENV", "DEV")).upper()
    if env not in CSV_BY_ENV:
        sys.exit(f"APP_ENV debe ser DEV o PRO, no '{env}'")

    conn = connect()
    cur = conn.cursor()

    if args.test:
        cur.execute(
            "select current_user(), current_role(), current_warehouse(), current_database()"
        )
        print("Conexión OK:", cur.fetchone())
        return

    csv_path = Path(os.environ[CSV_BY_ENV[env]])
    if not csv_path.is_file():
        sys.exit(f"No existe el archivo: {csv_path}")
    schema = f"{env}_BRONZE"
    size_mb = csv_path.stat().st_size / 1024**2
    print(f"Entorno {env}: {csv_path.name} ({size_mb:,.0f} MB) -> {schema}.{TABLE}")

    if env == "PRO" and not args.yes:
        if input("Vas a cargar el archivo COMPLETO en PRO. Escribe 'si' para continuar: ") != "si":
            sys.exit("Cancelado.")

    with csv_path.open(newline="", encoding="utf-8") as f:
        columns = [clean_column(c) for c in next(csv.reader(f))]

    cur.execute(f"use schema {schema}")
    # Algunas descripciones terminan en '\'; sin esto Snowflake lo toma como
    # escape de la coma siguiente y rompe la fila.
    cur.execute("alter file format CSV_FORMAT set escape_unenclosed_field = none")
    col_ddl = ", ".join(f"{c} varchar" for c in columns)
    cur.execute(f"create table if not exists {TABLE} ({col_ddl})")
    cur.execute(f"truncate table {TABLE}")

    # PUT comprime y trocea el archivo en paralelo
    stage = f"@{schema}.RAW_STAGE/{env.lower()}/"
    print("Subiendo al stage...")
    cur.execute(f"remove {stage}")
    cur.execute(f"put 'file://{csv_path.as_posix()}' {stage} auto_compress=true overwrite=true")

    print("COPY INTO...")
    cur.execute(f"copy into {TABLE} from {stage} file_format = (format_name = {schema}.CSV_FORMAT) force = true")
    cur.execute(f"select count(*) from {TABLE}")
    print(f"Filas cargadas en {schema}.{TABLE}: {cur.fetchone()[0]:,}")
    conn.close()


if __name__ == "__main__":
    main()
