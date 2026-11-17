"""Crea en Snowflake las 6 bases de datos del proyecto (idempotente).

  DEV_BRONZE_DB  DEV_SILVER_DB  DEV_GOLD_DB
  PRO_BRONZE_DB  PRO_SILVER_DB  PRO_GOLD_DB

Cada una con el esquema TRAFFIC_ACCIDENTS. En las de bronze además crea el
formato de archivo CSV_FORMAT y el stage interno RAW_STAGE donde se suben los CSV.

Uso:
  python scripts/setup_snowflake.py              # DEV y PRO
  python scripts/setup_snowflake.py --env DEV    # solo uno
"""
import argparse

from load_bronze import SCHEMA, connect

LAYERS = ("BRONZE", "SILVER", "GOLD")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", choices=["DEV", "PRO"], help="solo este entorno")
    args = parser.parse_args()
    envs = [args.env] if args.env else ["DEV", "PRO"]

    cur = connect().cursor()
    for env in envs:
        for layer in LAYERS:
            db = f"{env}_{layer}_DB"
            cur.execute(f"create database if not exists {db}")
            cur.execute(f"create schema if not exists {db}.{SCHEMA}")
            print(f"OK {db}.{SCHEMA}")
        bronze = f"{env}_BRONZE_DB.{SCHEMA}"
        cur.execute(
            f"create or replace file format {bronze}.CSV_FORMAT type = csv "
            "skip_header = 1 field_optionally_enclosed_by = '\"' "
            "null_if = ('') empty_field_as_null = true "
            # Algunas descripciones terminan en '\'; sin esto Snowflake lo toma
            # como escape de la coma siguiente y rompe la fila.
            "escape_unenclosed_field = none"
        )
        cur.execute(f"create stage if not exists {bronze}.RAW_STAGE")
        print(f"OK {bronze}.CSV_FORMAT, RAW_STAGE")


if __name__ == "__main__":
    main()
