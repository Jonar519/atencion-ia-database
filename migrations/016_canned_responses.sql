-- 016_canned_responses.sql
-- Fase 7, bloque B: respuestas predefinidas del panel.
--   Un admin las crea; un asesor inserta una en su caja de texto con un clic
--   (la edita si quiere y la envía como cualquier mensaje suyo: no hay envío
--   automático). Pueden llevar marcadores {cliente} y {asesor}, que reemplaza
--   el navegador antes de insertar.

CREATE TABLE canned_responses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       VARCHAR(80) NOT NULL CHECK (char_length(btrim(title)) >= 2),
  body        TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
  -- Atajo opcional para buscarla rápido ("saludo", "bloqueo-tarjeta").
  shortcut    VARCHAR(30) CHECK (shortcut IS NULL OR shortcut ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  is_active   BOOLEAN NOT NULL DEFAULT true,
  -- RESTRICT (como el resto del historial): una cuenta se anonimiza, no se borra.
  created_by  UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  updated_by  UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sin títulos ni atajos repetidos (sin distinguir mayúsculas).
CREATE UNIQUE INDEX uq_canned_responses_title ON canned_responses (lower(btrim(title)));
CREATE UNIQUE INDEX uq_canned_responses_shortcut ON canned_responses (shortcut) WHERE shortcut IS NOT NULL;

CREATE TRIGGER trg_canned_responses_updated_at
  BEFORE UPDATE ON canned_responses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
