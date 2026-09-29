-- 014_voice_hardening.sql
-- Reglas de la voz (Fase 5) garantizadas por la BASE, no solo por el backend.
--
-- 1. Un segmento de transcripción solo puede apuntar a un turno (messages) de
--    SU MISMA llamada. Antes bastaba con que el mensaje existiera: un bug podía
--    enlazar la transcripción de una llamada con el mensaje de otra (de otro
--    cliente, incluso), y el agente vería texto ajeno como parte de la llamada.
-- 2. Retención (docs/privacy-voice.md del backend): la transcripción se purga
--    al llegar a calls.retain_until. transcript_purged_at registra cuándo, y
--    una llamada purgada ya no admite segmentos nuevos.
-- 3. Tope de retención en el esquema: ninguna llamada puede pedir conservar su
--    transcripción más de 180 días, aunque el backend se configure mal.

-- 1. FK compuesta: (message_id, call_id) → messages(id, call_id).
--    Destino: UNIQUE (id, call_id) en messages (id ya es único; esto solo
--    habilita la FK compuesta). Con MATCH SIMPLE, un segmento sin mensaje
--    (message_id NULL) no se valida contra messages.
ALTER TABLE messages
  ADD CONSTRAINT uq_messages_id_call UNIQUE (id, call_id);

ALTER TABLE call_transcript_segments
  DROP CONSTRAINT call_transcript_segments_message_id_fkey;

-- ON DELETE SET NULL (message_id): si se borra el mensaje, el segmento queda
-- sin enlace (call_id es NOT NULL y no debe tocarse). Requiere PostgreSQL 15+.
ALTER TABLE call_transcript_segments
  ADD CONSTRAINT fk_call_transcript_segments_message_same_call
  FOREIGN KEY (message_id, call_id) REFERENCES messages (id, call_id)
  ON DELETE SET NULL (message_id);

-- 2. Purga por retención.
ALTER TABLE calls
  ADD COLUMN transcript_purged_at TIMESTAMPTZ;

-- Solo se purga una llamada terminada, y no antes de tiempo.
ALTER TABLE calls
  ADD CONSTRAINT chk_calls_purged_after_end
  CHECK (transcript_purged_at IS NULL OR (status IN ('ended', 'failed') AND transcript_purged_at >= ended_at));

CREATE FUNCTION call_transcript_segments_reject_purged()
RETURNS trigger AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM calls WHERE id = NEW.call_id AND transcript_purged_at IS NOT NULL) THEN
    RAISE EXCEPTION 'call_transcript_segments: la transcripción de la llamada % ya fue purgada', NEW.call_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_call_transcript_segments_reject_purged
  BEFORE INSERT OR UPDATE ON call_transcript_segments
  FOR EACH ROW EXECUTE FUNCTION call_transcript_segments_reject_purged();

-- Job de purga: llamadas vencidas y aún no purgadas.
CREATE INDEX idx_calls_pending_purge ON calls (retain_until) WHERE transcript_purged_at IS NULL;

-- 3. Tope de retención.
ALTER TABLE calls
  ADD CONSTRAINT chk_calls_retention_max CHECK (retain_until <= started_at + interval '180 days');
