-- 002_enums.sql
-- Tipos enumerados, definidos en un solo lugar y documentados aquí.
-- Añadir un valor más adelante: ALTER TYPE ... ADD VALUE en una migración
-- nueva (no se puede usar el valor nuevo dentro de la misma transacción).

-- ---------------------------------------------------------------------------
-- Staff
-- ---------------------------------------------------------------------------

-- Los permisos concretos se derivan del rol en el backend.
CREATE TYPE staff_role AS ENUM ('admin', 'agent');

-- Estado que el agente elige. La presencia real (conectado o no) vive en Redis.
CREATE TYPE agent_availability AS ENUM ('offline', 'available', 'busy', 'away');

-- ---------------------------------------------------------------------------
-- Conversaciones y mensajes
-- ---------------------------------------------------------------------------

-- ai_active ─▶ waiting_agent ─▶ agent_active ─▶ closed (desde cualquiera se puede cerrar)
CREATE TYPE conversation_status AS ENUM ('ai_active', 'waiting_agent', 'agent_active', 'closed');

CREATE TYPE conversation_close_reason AS ENUM (
  'resolved_by_ai',
  'resolved_by_agent',
  'customer_abandoned',
  'inactivity',
  'spam'
);

-- Canal de un turno. Un fragmento de voz transcrito es un mensaje con channel = 'voice'.
CREATE TYPE channel_type AS ENUM ('text', 'voice');

CREATE TYPE sender_type AS ENUM ('customer', 'ai', 'agent', 'system');

-- Análisis por turno del mensaje del cliente.
CREATE TYPE message_intent AS ENUM (
  'general_inquiry',  -- consulta simple
  'complaint',        -- reclamo
  'possible_fraud',   -- posible fraude (cargo no reconocido, robo de tarjeta…)
  'account_access',   -- no puede entrar, clave bloqueada
  'human_request',    -- pide explícitamente hablar con una persona
  'other'
);

CREATE TYPE message_sentiment AS ENUM ('positive', 'neutral', 'negative', 'angry');

-- ---------------------------------------------------------------------------
-- Llamadas
-- ---------------------------------------------------------------------------

-- connecting ─▶ in_progress ⇄ waiting_agent ─▶ ended | failed
CREATE TYPE call_status AS ENUM ('connecting', 'in_progress', 'waiting_agent', 'ended', 'failed');

CREATE TYPE call_end_reason AS ENUM ('customer_hangup', 'agent_hangup', 'timeout', 'error', 'transferred');

-- Quién participa de una llamada y quién habla en un segmento de transcripción.
CREATE TYPE participant_type AS ENUM ('customer', 'ai', 'agent');

-- ---------------------------------------------------------------------------
-- Escalamiento
-- ---------------------------------------------------------------------------

CREATE TYPE escalation_trigger AS ENUM (
  'rule',              -- regla determinista (ej.: palabra clave de fraude, N turnos sin resolver)
  'ai_signal',         -- señal del modelo (intención/sentimiento con confianza suficiente)
  'customer_request',  -- el cliente lo pidió
  'agent_manual'       -- un agente lo tomó por iniciativa propia
);

CREATE TYPE escalation_reason AS ENUM (
  'possible_fraud',
  'angry_customer',
  'complaint',
  'low_confidence',
  'human_requested',
  'repeated_failure',
  'voice_call'
);

-- open ─▶ assigned ─▶ resolved | cancelled
CREATE TYPE escalation_status AS ENUM ('open', 'assigned', 'resolved', 'cancelled');

-- ---------------------------------------------------------------------------
-- Base de conocimiento
-- ---------------------------------------------------------------------------

-- Solo los artículos 'published' alimentan el RAG.
CREATE TYPE kb_article_status AS ENUM ('draft', 'published', 'archived');

-- ---------------------------------------------------------------------------
-- Transversales
-- ---------------------------------------------------------------------------

CREATE TYPE actor_type AS ENUM ('staff', 'customer', 'system');

CREATE TYPE ai_usage_kind AS ENUM ('chat', 'classification', 'embedding', 'stt', 'tts');
