#!/usr/bin/env bash
# scripts/migrate.sh
# Aplica, en orden, las migraciones de migrations/ que todavía no se hayan
# aplicado a la base indicada en DATABASE_URL. Se puede correr las veces
# que se quiera: las ya aplicadas se saltan.
#
# Historial: tabla schema_migrations (filename, applied_at). Cada migración
# y su registro en el historial se ejecutan en UNA transacción: si la
# migración falla, no queda aplicada a medias ni marcada como aplicada.
#
# Uso local (con el docker-compose de este repo, que publica el puerto 5434):
#   export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"
#   ./scripts/migrate.sh
# (Lo usa la CI de GitHub Actions; en Windows usa scripts\migrate.bat.)

set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: define la variable de entorno DATABASE_URL antes de ejecutar este script."
  exit 1
fi

MIGRATIONS_DIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
# Oculta los NOTICE de Postgres (ej. "already exists, skipping"); los errores se siguen mostrando.
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X -q)

"${PSQL[@]}" -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  filename   VARCHAR(255) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

echo "Aplicando migraciones pendientes desde $MIGRATIONS_DIR ..."
pending=0
for file in "$MIGRATIONS_DIR"/*.sql; do
  name="$(basename "$file")"
  if [ "$("${PSQL[@]}" -tAc "SELECT 1 FROM schema_migrations WHERE filename = '$name'")" = "1" ]; then
    echo "   ya aplicada: $name"
    continue
  fi
  echo "-> aplicando $name"
  "${PSQL[@]}" --single-transaction -f "$file" -c "INSERT INTO schema_migrations (filename) VALUES ('$name')"
  pending=$((pending + 1))
done

echo "Listo: $pending migración(es) nueva(s) aplicada(s)."
