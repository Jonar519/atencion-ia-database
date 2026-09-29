@echo off
REM scripts\migrate.bat
REM Aplica, en orden, las migraciones de migrations\ que todavia no se hayan
REM aplicado, dentro del contenedor de Postgres del docker-compose de este
REM repo (no necesita psql instalado en Windows). Se puede correr las veces
REM que se quiera: las ya aplicadas se saltan.
REM
REM Historial: tabla schema_migrations (filename, applied_at). Cada migracion
REM y su registro en el historial se ejecutan en UNA transaccion: si la
REM migracion falla, no queda aplicada a medias ni marcada como aplicada.
REM
REM Uso (desde la carpeta atencion-ia-database, en cmd.exe):
REM     scripts\migrate.bat
REM Opcional: set DB_NAME=otra_base   (por defecto atencion_ia)

setlocal enabledelayedexpansion

if "%CONTAINER%"=="" set CONTAINER=atencion_ia_postgres
if "%DB_NAME%"=="" set DB_NAME=atencion_ia
if "%DB_USER%"=="" set DB_USER=postgres
REM Oculta los NOTICE de Postgres. Se pasa al contenedor con "-e PGOPTIONS"
REM (sin "="): dentro de "for /f", cmd.exe trata "=" como separador.
set "PGOPTIONS=-c client_min_messages=warning"
set PSQL=docker exec -i -e PGOPTIONS %CONTAINER% psql -U %DB_USER% -d %DB_NAME% -v ON_ERROR_STOP=1 -X -q

%PSQL% -c "CREATE TABLE IF NOT EXISTS schema_migrations (filename VARCHAR(255) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"
if errorlevel 1 (
    echo ERROR: no se pudo conectar a la base %DB_NAME% en el contenedor %CONTAINER%.
    echo        Levantalo con "docker compose up -d" y espera a que este healthy.
    exit /b 1
)

echo Aplicando migraciones pendientes...
set PENDING=0
for %%f in (migrations\*.sql) do (
    set "APPLIED="
    for /f "usebackq delims=" %%a in (`%PSQL% -tAc "SELECT 1 FROM schema_migrations WHERE filename = '%%~nxf'"`) do set APPLIED=%%a
    if "!APPLIED!"=="1" (
        echo    ya aplicada: %%~nxf
    ) else (
        echo -^> aplicando %%~nxf
        %PSQL% --single-transaction -f - -c "INSERT INTO schema_migrations (filename) VALUES ('%%~nxf')" < "%%f"
        if errorlevel 1 (
            echo ERROR al aplicar %%~nxf
            exit /b 1
        )
        set /a PENDING+=1
    )
)

echo Listo: !PENDING! migracion^(es^) nueva^(s^) aplicada^(s^).
