-- 006_customers.sql
-- Clientes finales (quienes escriben o llaman) y sus sesiones de widget.
--
-- Un cliente NO tiene contraseña: se identifica con un token opaco que el
-- backend entrega al widget. Todos los datos de contacto son opcionales (un
-- cliente anónimo es válido). Si en el futuro los clientes tienen cuenta, se
-- añade una tabla customer_credentials (1:1) sin tocar esta ni nada de lo que
-- cuelga de ella.

CREATE TABLE customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name  VARCHAR(120) CHECK (display_name IS NULL OR length(btrim(display_name)) > 0),
  email         VARCHAR(254)
                  CHECK (email IS NULL OR (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  -- Formato E.164 laxo: + opcional y 7-15 dígitos.
  phone         VARCHAR(16) CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{7,15}$'),
  -- Identificador del cliente en el CRM de la empresa, si lo hay.
  external_ref  VARCHAR(100),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Únicos solo cuando existen (muchos clientes anónimos no tienen correo).
CREATE UNIQUE INDEX uq_customers_email ON customers (email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX uq_customers_external_ref ON customers (external_ref) WHERE external_ref IS NOT NULL;

CREATE TRIGGER trg_customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Sesiones del widget. Solo se guarda el SHA-256 del token.
-- ip_hash: HMAC de la IP (lo calcula el backend con un secreto), útil para
-- detectar abuso sin guardar la IP en claro.
CREATE TABLE widget_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  token_hash    CHAR(64) NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ NOT NULL,
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at    TIMESTAMPTZ,
  user_agent    VARCHAR(200),
  ip_hash       CHAR(64) CHECK (ip_hash IS NULL OR ip_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT uq_widget_sessions_token UNIQUE (token_hash),
  CONSTRAINT chk_widget_sessions_expiry CHECK (expires_at > created_at)
);

CREATE INDEX idx_widget_sessions_customer ON widget_sessions (customer_id, created_at DESC);
CREATE INDEX idx_widget_sessions_expires ON widget_sessions (expires_at);
