@echo off
REM scripts\seed.bat
REM Carga los datos de prueba dentro del contenedor de Postgres.
REM Los archivos de seed\ son idempotentes: se pueden ejecutar varias veces
REM sin duplicar datos. Cada archivo corre en una transaccion.
REM
REM Contrasena de todos los usuarios de prueba (staff): Password123!
REM
REM Uso (desde la carpeta atencion-ia-database, en cmd.exe):
REM     scripts\seed.bat
REM Opcional: set DB_NAME=otra_base   (por defecto atencion_ia)

setlocal enabledelayedexpansion

if "%CONTAINER%"=="" set CONTAINER=atencion_ia_postgres
if "%DB_NAME%"=="" set DB_NAME=atencion_ia
if "%DB_USER%"=="" set DB_USER=postgres
set "PGOPTIONS=-c client_min_messages=warning"

echo Cargando datos de prueba...

for %%f in (seed\*.sql) do (
    echo -^> cargando %%f
    docker exec -i -e PGOPTIONS %CONTAINER% psql -U %DB_USER% -d %DB_NAME% -v ON_ERROR_STOP=1 -X -q --single-transaction -f - < "%%f"
    if errorlevel 1 (
        echo ERROR al cargar %%f
        exit /b 1
    )
)

echo Datos de prueba cargados correctamente.
