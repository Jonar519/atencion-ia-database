-- 009_calls.sql
-- Llamadas de voz (WebRTC en el navegador) y quién participó en cada una.
-- Va antes que messages porque un turno de voz referencia su llamada.

CREATE TABLE calls (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id      UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  status               call_status NOT NULL DEFAULT 'connecting',
  -- No puede existir una llamada sin consentimiento registrado.
  consent_given_at     TIMESTAMPTZ NOT NULL,
  -- Versión del texto de aviso que el cliente aceptó (docs/privacy-voice.md).
  consent_version      VARCHAR(20) NOT NULL,
  started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  answered_at          TIMESTAMPTZ,
  ended_at             TIMESTAMPTZ,
  -- Calculada: nunca contradice las marcas de tiempo.
  duration_seconds     INT GENERATED ALWAYS AS (
                         CASE WHEN answered_at IS NOT NULL AND ended_at IS NOT NULL
                              THEN extract(epoch FROM (ended_at - answered_at))::int
                         END
                       ) STORED,
  -- Agente humano que la atendió (NULL = solo la IA).
  handled_by_agent_id  UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  end_reason           call_end_reason,
  stt_provider         VARCHAR(40) NOT NULL,
  tts_provider         VARCHAR(40) NOT NULL,
  -- El audio NO se guarda por defecto: NULL salvo que la política lo pida.
  audio_storage_key    VARCHAR(500),
  -- A partir de esta fecha se purga la transcripción (política de retención).
  retain_until         TIMESTAMPTZ NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Destino de las FK compuestas (messages, escalations): garantiza que un
  -- turno o escalamiento que apunta a esta llamada es de la MISMA conversación.
  CONSTRAINT uq_calls_id_conversation UNIQUE (id, conversation_id),
  CONSTRAINT chk_calls_consent_first CHECK (consent_given_at <= started_at),
  CONSTRAINT chk_calls_answered_after_start CHECK (answered_at IS NULL OR answered_at >= started_at),
  CONSTRAINT chk_calls_ended_after_start CHECK (ended_at IS NULL OR ended_at >= started_at),
  -- Terminada ⇔ tiene fecha de fin; el motivo solo existe si terminó.
  CONSTRAINT chk_calls_ended
    CHECK ((status IN ('ended', 'failed')) = (ended_at IS NOT NULL)),
  CONSTRAINT chk_calls_end_reason
    CHECK (end_reason IS NULL OR status IN ('ended', 'failed')),
  CONSTRAINT chk_calls_retention CHECK (retain_until > started_at)
);

-- Llamadas de una conversación, recientes primero (cubre también la FK).
CREATE INDEX idx_calls_conversation ON calls (conversation_id, started_at DESC);

-- Como máximo UNA llamada activa por conversación.
CREATE UNIQUE INDEX uq_calls_one_active_per_conversation
  ON calls (conversation_id)
  WHERE status IN ('connecting', 'in_progress', 'waiting_agent');

-- Panel de agente: "llamadas en curso".
CREATE INDEX idx_calls_active
  ON calls (status, started_at)
  WHERE status IN ('connecting', 'in_progress', 'waiting_agent');

CREATE INDEX idx_calls_handled_by ON calls (handled_by_agent_id) WHERE handled_by_agent_id IS NOT NULL;

-- Job de purga por retención.
CREATE INDEX idx_calls_retain_until ON calls (retain_until);

CREATE TRIGGER trg_calls_updated_at
  BEFORE UPDATE ON calls
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Quién estuvo en la llamada y cuándo. Aquí queda registrado que un agente
-- "se unió" a una llamada en curso.
CREATE TABLE call_participants (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id           UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  participant_type  participant_type NOT NULL,
  agent_id          UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  joined_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at           TIMESTAMPTZ,
  -- Solo los participantes 'agent' tienen agente.
  CONSTRAINT chk_call_participants_agent CHECK ((participant_type = 'agent') = (agent_id IS NOT NULL)),
  CONSTRAINT chk_call_participants_left CHECK (left_at IS NULL OR left_at >= joined_at)
);

CREATE INDEX idx_call_participants_call ON call_participants (call_id, joined_at);
CREATE INDEX idx_call_participants_agent ON call_participants (agent_id, joined_at DESC) WHERE agent_id IS NOT NULL;

-- Un agente no puede estar "unido" dos veces a la vez a la misma llamada.
CREATE UNIQUE INDEX uq_call_participants_agent_present
  ON call_participants (call_id, agent_id)
  WHERE left_at IS NULL AND agent_id IS NOT NULL;
