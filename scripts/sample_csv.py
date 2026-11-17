"""Genera una muestra determinista del CSV original para desarrollo.

Selecciona las filas cuyo hash del ID cae en el porcentaje indicado, así la
muestra es siempre la misma y es un subconjunto exacto del original.
Lee por bloques para no cargar 3 GB en memoria.
"""
import os

import pandas as pd
from dotenv import load_dotenv
from pandas.util import hash_pandas_object

load_dotenv()

SRC = os.environ["PRO_CSV_1"]
DST = os.environ["DEV_CSV_1"]
PERCENT = int(os.getenv("SAMPLE_PERCENT", "10"))
CHUNK = 500_000


def main() -> None:
    total = kept = 0
    first = True
    for chunk in pd.read_csv(SRC, dtype=str, keep_default_na=False, chunksize=CHUNK):
        mask = hash_pandas_object(chunk["ID"], index=False) % 100 < PERCENT
        sample = chunk[mask]
        sample.to_csv(DST, mode="w" if first else "a", header=first, index=False)
        first = False
        total += len(chunk)
        kept += len(sample)
        print(f"procesadas {total:,} filas, muestra {kept:,}")
    print(f"Listo: {kept:,} de {total:,} ({kept / total:.1%}) -> {DST}")


if __name__ == "__main__":
    main()
