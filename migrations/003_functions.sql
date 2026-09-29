-- 003_functions.sql
-- Funciones compartidas por varias tablas.

-- updated_at automático: cada tabla con updated_at crea su trigger
-- BEFORE UPDATE en su propia migración. Así el valor es correcto aunque la
-- fila se modifique desde psql o desde otro servicio, no solo desde Prisma.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
