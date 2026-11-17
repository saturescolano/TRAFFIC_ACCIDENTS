"""Carga los CSV de un entorno en la capa bronze de Snowflake.

Cada entorno tiene DOS orígenes (si no se define *_CSV_2 se usa el mismo
archivo que *_CSV_1, es decir, el dato queda duplicado a propósito):

  APP_ENV=DEV -> DEV_CSV_1 -> DEV_BRONZE_DB.TRAFFIC_ACCIDENTS.RAW_ACCIDENTS_1
                 DEV_CSV_2 -> DEV_BRONZE_DB.TRAFFIC_ACCIDENTS.RAW_ACCIDENTS_2
  APP_ENV=PRO -> PRO_CSV_1 / PRO_CSV_2 -> PRO_BRONZE_DB ...

El UNION ALL de ambos orígenes lo hace dbt (modelo bronze_accidents).
Requiere haber ejecutado antes scripts/setup_snowflake.py.

Uso:
  python scripts/load_bronze.py --test          # solo prueba la conexión
  python scripts/load_bronze.py                 # usa APP_ENV del .env
  python scripts/load_bronze.py --env PRO       # fuerza el entorno

Todas las columnas se cargan como VARCHAR (bronze = dato crudo). El tipado
se hace después en silver. Cada carga hace TRUNCATE + COPY, así que repetirla
no duplica filas.
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

SCHEMA = "TRAFFIC_ACCIDENTS"
ORIGINS = (1, 2)


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
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", choices=["DEV", "PRO"], help="sobrescribe APP_ENV")
    parser.add_argument("--test", action="store_true", help="solo probar la conexión")
    parser.add_argument("--yes", action="store_true", help="no pedir confirmación en PRO")
    args = parser.parse_args()

    env = (args.env or os.getenv("APP_ENV", "DEV")).upper()
    if env not in ("DEV", "PRO"):
        sys.exit(f"APP_ENV debe ser DEV o PRO, no '{env}'")

    conn = connect()
    cur = conn.cursor()

    if args.test:
        cur.execute("select current_user(), current_role(), current_warehouse()")
        print("Conexión OK:", cur.fetchone())
        return

    # Origen 2 sin definir -> mismo archivo que el 1 (duplicado)
    csv_1 = os.getenv(f"{env}_CSV_1")
    if not csv_1:
        sys.exit(f"Falta {env}_CSV_1 en el .env")
    csvs = {1: Path(csv_1), 2: Path(os.getenv(f"{env}_CSV_2") or csv_1)}
    for path in csvs.values():
        if not path.is_file():
            sys.exit(f"No existe el archivo: {path}")

    database = f"{env}_BRONZE_DB"
    qualified = f"{database}.{SCHEMA}"
    print(f"Entorno {env} -> {qualified}")

    if env == "PRO" and not args.yes:
        if input("Vas a cargar el archivo COMPLETO en PRO (x2). Escribe 'si' para continuar: ") != "si":
            sys.exit("Cancelado.")

    cur.execute(f"use schema {qualified}")

    for n in ORIGINS:
        path, table = csvs[n], f"RAW_ACCIDENTS_{n}"
        size_mb = path.stat().st_size / 1024**2
        print(f"[origen {n}] {path.name} ({size_mb:,.0f} MB) -> {table}")

        with path.open(newline="", encoding="utf-8") as f:
            columns = [clean_column(c) for c in next(csv.reader(f))]
        col_ddl = ", ".join(f"{c} varchar" for c in columns)
        cur.execute(f"create table if not exists {table} ({col_ddl})")
        cur.execute(f"truncate table {table}")

        # PUT comprime y trocea el archivo en paralelo
        stage = f"@{qualified}.RAW_STAGE/origin_{n}/"
        cur.execute(f"remove {stage}")
        cur.execute(f"put 'file://{path.as_posix()}' {stage} auto_compress=true overwrite=true")
        cur.execute(
            f"copy into {table} from {stage} "
            f"file_format = (format_name = {qualified}.CSV_FORMAT) force = true"
        )
        cur.execute(f"select count(*) from {table}")
        print(f"  filas en {table}: {cur.fetchone()[0]:,}")
    conn.close()


if __name__ == "__main__":
    main()
