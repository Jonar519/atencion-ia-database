#!/usr/bin/env bash
# scripts/seed.sh
# Carga los datos de prueba. Solo para entornos de desarrollo/demo.
#
# Los archivos de seed/ son idempotentes (ON CONFLICT): se pueden ejecutar
# varias veces sin duplicar datos, por eso no se registran en
# schema_migrations. Cada archivo corre en una transacción.
#
# Contraseña de todos los usuarios de prueba (staff): Password123!
#
# Uso (con el docker-compose de este repo, que publica el puerto 5434):
#   export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"
#   ./scripts/seed.sh

set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: define la variable de entorno DATABASE_URL antes de ejecutar este script."
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
SEED_DIR="$(cd "$(dirname "$0")/../seed" && pwd)"

for file in "$SEED_DIR"/*.sql; do
  echo "-> cargando $(basename "$file")"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X -q --single-transaction -f "$file"
done

echo "Datos de prueba cargados correctamente."
