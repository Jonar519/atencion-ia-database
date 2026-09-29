#!/usr/bin/env bash
# scripts/test.sh
# Ejecuta las pruebas del esquema (tests/*.sql). Cada archivo corre en una
# transacción que termina en ROLLBACK: no deja datos. Requiere la base
# migrada (scripts/migrate.sh). Lo usa la CI de GitHub Actions.
#
# Uso:
#   export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"
#   ./scripts/test.sh

set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: define la variable de entorno DATABASE_URL antes de ejecutar este script."
  exit 1
fi

TESTS_DIR="$(cd "$(dirname "$0")/../tests" && pwd)"

for file in "$TESTS_DIR"/*.sql; do
  echo "-> $(basename "$file")"
  psql "$DATABASE_URL" -X -q -f "$file"
done

echo "Todas las pruebas del esquema pasaron."
