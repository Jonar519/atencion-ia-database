-- 008_conversations.sql
-- Un hilo de atención de un cliente: solo texto, solo voz o mixto.
--
-- "Mixta" no se guarda: se deduce de sus mensajes/llamadas (evita un dato que
-- se desincroniza). origin_channel solo dice por dónde empezó.
--
-- ON DELETE CASCADE desde customers: borrar a un cliente (derecho de
-- supresión) borra sus conversaciones y todo lo que cuelga de ellas.
-- ON DELETE RESTRICT hacia staff_users: los agentes se desactivan, no se borran.

CREATE TABLE conversations (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id        UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  assigned_agent_id  UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  status             conversation_status NOT NULL DEFAULT 'ai_active',
  origin_channel     channel_type NOT NULL,
  subject            VARCHAR(200),
  -- 0-100. La sube el motor de escalamiento (fraude > cliente molesto > reclamo…).
  priority           SMALLINT NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 100),
  -- Desnormalizado para ordenar listas sin agregar sobre messages.
  last_message_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at          TIMESTAMPTZ,
  close_reason       conversation_close_reason,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Atendida por un humano ⇒ tiene agente.
  CONSTRAINT chk_conversations_agent_active
    CHECK (status <> 'agent_active' OR assigned_agent_id IS NOT NULL),
  -- Cerrada ⇔ tiene fecha de cierre y motivo.
  CONSTRAINT chk_conversations_closed
    CHECK ((status = 'closed') = (closed_at IS NOT NULL)
       AND (status = 'closed') = (close_reason IS NOT NULL)),
  CONSTRAINT chk_conversations_closed_after_created
    CHECK (closed_at IS NULL OR closed_at >= created_at)
);

-- Cola general: en espera, sin agente, la más urgente y la que más espera primero.
CREATE INDEX idx_conversations_queue
  ON conversations (priority DESC, last_message_at ASC)
  WHERE status = 'waiting_agent' AND assigned_agent_id IS NULL;

-- "Mis conversaciones" de un agente, recientes primero (cubre también la FK).
CREATE INDEX idx_conversations_agent
  ON conversations (assigned_agent_id, status, last_message_at DESC);

-- Historial de un cliente (cubre también la FK).
CREATE INDEX idx_conversations_customer
  ON conversations (customer_id, created_at DESC);

-- Listados del admin filtrados por estado.
CREATE INDEX idx_conversations_status_last
  ON conversations (status, last_message_at DESC);

CREATE TRIGGER trg_conversations_updated_at
  BEFORE UPDATE ON conversations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
