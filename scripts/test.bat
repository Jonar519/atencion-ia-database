@echo off
REM scripts\test.bat
REM Ejecuta las pruebas del esquema (tests\*.sql) dentro del contenedor de
REM Postgres. Cada archivo corre en una transaccion que termina en ROLLBACK:
REM no deja datos. Requiere la base migrada (scripts\migrate.bat).
REM
REM Uso (desde la carpeta atencion-ia-database, en cmd.exe):
REM     scripts\test.bat
REM Opcional: set DB_NAME=otra_base   (por defecto atencion_ia)

setlocal enabledelayedexpansion

if "%CONTAINER%"=="" set CONTAINER=atencion_ia_postgres
if "%DB_NAME%"=="" set DB_NAME=atencion_ia
if "%DB_USER%"=="" set DB_USER=postgres

for %%f in (tests\*.sql) do (
    echo -^> %%f
    docker exec -i %CONTAINER% psql -U %DB_USER% -d %DB_NAME% -X -q -f - < "%%f"
    if errorlevel 1 (
        echo PRUEBAS FALLIDAS en %%f
        exit /b 1
    )
)

echo Todas las pruebas del esquema pasaron.
