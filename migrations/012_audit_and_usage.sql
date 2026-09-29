-- 012_audit_and_usage.sql
-- Registro de auditoría y consumo de proveedores de IA/voz.

-- Quién hizo qué, sobre qué y cuándo. Sin datos sensibles: ni contraseñas,
-- ni tokens, ni contenido de mensajes o transcripciones. Solo la acción, la
-- entidad y su id, y metadatos no sensibles.
--
-- actor_id sin FK: es polimórfico (staff_users o customers) y el registro
-- debe sobrevivir a que se borre el actor. Es NULL en intentos fallidos de
-- login (no se guarda el correo intentado) y en acciones del sistema.
CREATE TABLE audit_log (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_type   actor_type NOT NULL,
  actor_id     UUID,
  -- Formato dominio.accion: auth.login, conversation.take, kb.update, call.join…
  action       VARCHAR(60) NOT NULL CHECK (action ~ '^[a-z_]+(\.[a-z_]+)+$'),
  entity_type  VARCHAR(40),
  entity_id    VARCHAR(64),
  metadata     JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  -- HMAC de la IP (lo calcula el backend), no la IP en claro.
  ip_hash      CHAR(64) CHECK (ip_hash IS NULL OR ip_hash ~ '^[0-9a-f]{64}$'),
  user_agent   VARCHAR(200),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_audit_log_system_actor CHECK (actor_type <> 'system' OR actor_id IS NULL)
);

CREATE INDEX idx_audit_log_created ON audit_log (created_at DESC);
CREATE INDEX idx_audit_log_actor ON audit_log (actor_type, actor_id, created_at DESC);
CREATE INDEX idx_audit_log_entity ON audit_log (entity_type, entity_id);

-- Cada llamada a un proveedor que cuesta dinero. Sirve para:
--   * topes de gasto por cliente (defensa contra agotar créditos de IA, por
--     ejemplo manteniendo abierto el canal de voz);
--   * el reporte de costos.
-- SET NULL: el registro de consumo sobrevive al borrado del cliente, anónimo.
CREATE TABLE ai_usage (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind                ai_usage_kind NOT NULL,
  provider            VARCHAR(40) NOT NULL,
  model               VARCHAR(80),
  conversation_id     UUID REFERENCES conversations(id) ON DELETE SET NULL,
  customer_id         UUID REFERENCES customers(id) ON DELETE SET NULL,
  call_id             UUID REFERENCES calls(id) ON DELETE SET NULL,
  -- tokens (chat/clasificación/embeddings), seconds (STT), characters (TTS).
  unit                VARCHAR(20) NOT NULL CHECK (unit IN ('tokens', 'seconds', 'characters')),
  input_units         INT NOT NULL DEFAULT 0 CHECK (input_units >= 0),
  output_units        INT NOT NULL DEFAULT 0 CHECK (output_units >= 0),
  estimated_cost_usd  NUMERIC(12, 6) NOT NULL DEFAULT 0 CHECK (estimated_cost_usd >= 0),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Consumo de un cliente en una ventana de tiempo (tope de gasto).
CREATE INDEX idx_ai_usage_customer ON ai_usage (customer_id, created_at) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_ai_usage_conversation ON ai_usage (conversation_id) WHERE conversation_id IS NOT NULL;
CREATE INDEX idx_ai_usage_call ON ai_usage (call_id) WHERE call_id IS NOT NULL;
-- Reporte de costos por periodo y tipo.
CREATE INDEX idx_ai_usage_created_kind ON ai_usage (created_at, kind);
