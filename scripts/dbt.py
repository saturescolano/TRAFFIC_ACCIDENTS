"""Ejecuta dbt cargando antes el .env (APP_ENV, credenciales, materializaciones).

  python scripts/dbt.py debug
  python scripts/dbt.py build                    # usa APP_ENV del .env
  APP_ENV=PRO en el .env (o en el entorno) para producción
"""
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

dbt_dir = ROOT / "dbt"
cmd = [str(Path(sys.executable).with_name("dbt")), *sys.argv[1:]]
cmd += ["--project-dir", str(dbt_dir), "--profiles-dir", str(dbt_dir)]
print(f"[APP_ENV={os.getenv('APP_ENV', 'DEV')}]", " ".join(sys.argv[1:]))
sys.exit(subprocess.call(cmd))
