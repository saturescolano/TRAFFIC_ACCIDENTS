# Prepara la terminal para usar `dbt` directamente desde la raíz del repo.
# Uso (una vez por terminal, con el punto delante):
#   . .\scripts\env.ps1
#   dbt test
#
# Hace dos cosas:
#   1. Carga las variables del .env (credenciales, APP_ENV...) en la sesión.
#   2. Apunta dbt a la carpeta dbt/ (DBT_PROJECT_DIR y DBT_PROFILES_DIR).

$root = Split-Path -Parent $PSScriptRoot

$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) {
    Write-Warning "No existe $envFile (copia .env.example a .env)."
    return
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $name, $value = $line -split "=", 2
        Set-Item -Path "Env:$($name.Trim())" -Value $value.Trim().Trim('"').Trim("'")
    }
}

$env:DBT_PROJECT_DIR  = Join-Path $root "dbt"
$env:DBT_PROFILES_DIR = Join-Path $root "dbt"

$appEnv = if ($env:APP_ENV) { $env:APP_ENV } else { "DEV" }
Write-Host "dbt listo [APP_ENV=$appEnv]. Ejecuta p. ej.: dbt test"
