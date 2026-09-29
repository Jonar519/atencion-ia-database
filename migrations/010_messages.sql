-- 010_messages.sql
-- Turnos de la conversación, citas del RAG y transcripción de las llamadas.
--
-- Decisión central del modelo: un fragmento de voz transcrito es un mensaje
-- más (channel = 'voice', call_id = la llamada). El motor conversacional no
-- distingue el canal de entrada.

CREATE TABLE messages (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id      UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_type          sender_type NOT NULL,
  sender_agent_id      UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  channel              channel_type NOT NULL DEFAULT 'text',
  call_id              UUID,
  content              TEXT NOT NULL CHECK (length(btrim(content)) > 0 AND length(content) <= 8000),
  -- Análisis por turno (solo mensajes del cliente).
  intent               message_intent,
  sentiment            message_sentiment,
  analysis_confidence  REAL CHECK (analysis_confidence IS NULL OR analysis_confidence BETWEEN 0 AND 1),
  -- UUID generado por el cliente: un reenvío tras reconectar el WebSocket
  -- no duplica el mensaje (ver UNIQUE abajo).
  client_msg_id        UUID,
  -- Observabilidad de las respuestas de la IA.
  ai_model             VARCHAR(80),
  ai_latency_ms        INT CHECK (ai_latency_ms IS NULL OR ai_latency_ms >= 0),
  -- clock_timestamp() y no now(): el mensaje del cliente y la respuesta de la
  -- IA se insertan en la misma transacción y con now() empatarían.
  created_at           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  -- Un turno de voz pertenece a una llamada DE ESTA MISMA conversación.
  CONSTRAINT fk_messages_call FOREIGN KEY (call_id, conversation_id)
    REFERENCES calls (id, conversation_id),
  -- Destino de la FK compuesta de escalations.triggering_message_id.
  CONSTRAINT uq_messages_id_conversation UNIQUE (id, conversation_id),
  CONSTRAINT uq_messages_client_msg UNIQUE (conversation_id, client_msg_id),
  -- Solo los mensajes de agente tienen agente, y siempre lo tienen.
  CONSTRAINT chk_messages_agent CHECK ((sender_type = 'agent') = (sender_agent_id IS NOT NULL)),
  -- Voz ⇔ tiene llamada.
  CONSTRAINT chk_messages_voice_call CHECK ((channel = 'voice') = (call_id IS NOT NULL)),
  CONSTRAINT chk_messages_analysis_only_customer
    CHECK (sender_type = 'customer' OR (intent IS NULL AND sentiment IS NULL AND analysis_confidence IS NULL)),
  CONSTRAINT chk_messages_ai_fields_only_ai
    CHECK (sender_type = 'ai' OR (ai_model IS NULL AND ai_latency_ms IS NULL))
);

-- Mensajes de una conversación en orden (cubre también la FK). id desempata.
CREATE INDEX idx_messages_conversation ON messages (conversation_id, created_at, id);
-- Turnos de una llamada.
CREATE INDEX idx_messages_call ON messages (call_id, created_at) WHERE call_id IS NOT NULL;
CREATE INDEX idx_messages_sender_agent ON messages (sender_agent_id) WHERE sender_agent_id IS NOT NULL;

-- Qué fragmentos de la KB usó la IA para responder: el agente ve "de dónde
-- sacó eso" y el RAG se puede auditar. Si el artículo se re-indexa o se borra
-- la cita sobrevive (SET NULL) con la versión con la que se generó.
CREATE TABLE message_citations (
  message_id       UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  rank             SMALLINT NOT NULL CHECK (rank >= 1),
  article_id       UUID REFERENCES kb_articles(id) ON DELETE SET NULL,
  chunk_id         UUID REFERENCES kb_chunks(id) ON DELETE SET NULL,
  article_version  INT NOT NULL CHECK (article_version >= 1),
  -- Similitud coseno.
  score            REAL NOT NULL CHECK (score BETWEEN -1 AND 1),
  PRIMARY KEY (message_id, rank)
);

CREATE INDEX idx_message_citations_article ON message_citations (article_id) WHERE article_id IS NOT NULL;
CREATE INDEX idx_message_citations_chunk ON message_citations (chunk_id) WHERE chunk_id IS NOT NULL;

-- Transcripción completa de una llamada, en orden. Solo segmentos FINALES:
-- los resultados parciales del STT en streaming viajan por WebSocket y no se
-- guardan. Cada segmento final se convierte en un turno (message_id).
CREATE TABLE call_transcript_segments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id     UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  seq         INT NOT NULL CHECK (seq >= 0),
  speaker     participant_type NOT NULL,
  text        TEXT NOT NULL CHECK (length(btrim(text)) > 0 AND length(text) <= 4000),
  -- Milisegundos desde el inicio de la llamada.
  start_ms    INT NOT NULL CHECK (start_ms >= 0),
  end_ms      INT NOT NULL,
  confidence  REAL CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  message_id  UUID REFERENCES messages(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  -- (call_id, seq) también sirve de índice para la FK y para leer en orden.
  CONSTRAINT uq_call_transcript_segments_seq UNIQUE (call_id, seq),
  -- Un turno corresponde a un solo segmento.
  CONSTRAINT uq_call_transcript_segments_message UNIQUE (message_id),
  CONSTRAINT chk_call_transcript_segments_times CHECK (end_ms >= start_ms)
);
