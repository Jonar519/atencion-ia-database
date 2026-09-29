-- 011_escalations.sql
-- Cuándo y por qué una conversación pasó de la IA a un humano, con la señal
-- que lo disparó.
--
-- SIN DUPLICADOS ABIERTOS: el índice único parcial de abajo garantiza como
-- máximo un escalamiento 'open' o 'assigned' por conversación. Si dos turnos
-- simultáneos deciden escalar, uno inserta y el otro choca con el índice; el
-- backend usa INSERT … ON CONFLICT DO NOTHING y lo trata como "ya estaba
-- escalada". La garantía la da la base, no un SELECT previo con carrera.

CREATE TABLE escalations (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id        UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  -- Si ocurrió durante una llamada.
  call_id                UUID,
  triggering_message_id  UUID,
  trigger_source         escalation_trigger NOT NULL,
  reason                 escalation_reason NOT NULL,
  -- Evidencia concreta: regla aplicada, puntajes de intención/sentimiento,
  -- turnos sin resolver… Nunca el texto del mensaje (ya está en messages).
  signal                 JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(signal) = 'object'),
  priority               SMALLINT NOT NULL DEFAULT 50 CHECK (priority BETWEEN 0 AND 100),
  status                 escalation_status NOT NULL DEFAULT 'open',
  assigned_agent_id      UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  assigned_at            TIMESTAMPTZ,
  resolved_at            TIMESTAMPTZ,
  resolution_note        VARCHAR(500),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- La llamada y el mensaje que lo dispararon son de ESTA conversación.
  CONSTRAINT fk_escalations_call FOREIGN KEY (call_id, conversation_id)
    REFERENCES calls (id, conversation_id),
  CONSTRAINT fk_escalations_message FOREIGN KEY (triggering_message_id, conversation_id)
    REFERENCES messages (id, conversation_id),
  -- Asignado ⇒ tiene agente y fecha de asignación.
  CONSTRAINT chk_escalations_assigned
    CHECK (status <> 'assigned' OR (assigned_agent_id IS NOT NULL AND assigned_at IS NOT NULL)),
  CONSTRAINT chk_escalations_agent_has_date
    CHECK ((assigned_agent_id IS NULL) = (assigned_at IS NULL)),
  -- Terminado (resuelto o cancelado) ⇔ tiene fecha de cierre.
  CONSTRAINT chk_escalations_resolved
    CHECK ((status IN ('resolved', 'cancelled')) = (resolved_at IS NOT NULL)),
  CONSTRAINT chk_escalations_assigned_after_created CHECK (assigned_at IS NULL OR assigned_at >= created_at),
  CONSTRAINT chk_escalations_resolved_after_created CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

-- Como máximo UN escalamiento abierto por conversación.
CREATE UNIQUE INDEX uq_escalations_one_open_per_conversation
  ON escalations (conversation_id)
  WHERE status IN ('open', 'assigned');

-- Bandeja de escalamientos: los más urgentes y antiguos primero. El estado va
-- en el predicado parcial y no como primera columna: con status IN (dos
-- valores) como columna inicial, el índice no entrega las filas ya ordenadas
-- por prioridad y Postgres tendría que ordenar.
CREATE INDEX idx_escalations_inbox
  ON escalations (priority DESC, created_at)
  WHERE status IN ('open', 'assigned');

-- Historial de escalamientos de una conversación (cubre también la FK).
CREATE INDEX idx_escalations_conversation ON escalations (conversation_id, created_at DESC);
CREATE INDEX idx_escalations_agent ON escalations (assigned_agent_id, created_at DESC) WHERE assigned_agent_id IS NOT NULL;
CREATE INDEX idx_escalations_call ON escalations (call_id) WHERE call_id IS NOT NULL;
CREATE INDEX idx_escalations_message ON escalations (triggering_message_id) WHERE triggering_message_id IS NOT NULL;

CREATE TRIGGER trg_escalations_updated_at
  BEFORE UPDATE ON escalations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
