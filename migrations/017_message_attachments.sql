-- 017_message_attachments.sql
-- Fase 7, bloque C: adjuntos en el chat de texto (imagen o PDF).
--   - El ARCHIVO vive en el almacenamiento (local o S3); aquí solo sus datos.
--   - Un adjunto por mensaje, y siempre de un mensaje de SU conversación
--     (FK compuesta, como la transcripción en la 014).
--   - Tipos y tamaño máximo los impone también la base.
--   - Borrar el mensaje (o al cliente, en cascada) encola el archivo para
--     borrarlo del almacenamiento (storage_deletions): no quedan huérfanos.
--   - El nombre original es SOLO para mostrarlo; nunca llega a la IA
--     (lo controla quien sube el archivo: puede traer instrucciones).

CREATE TABLE message_attachments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id       UUID NOT NULL,
  conversation_id  UUID NOT NULL,
  -- Clave generada por el servidor, nunca el nombre que manda el usuario.
  storage_key      VARCHAR(300) NOT NULL UNIQUE
    CHECK (storage_key ~ '^attachments/[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|jpg|webp|pdf)$'),
  content_type     VARCHAR(40) NOT NULL
    CHECK (content_type IN ('image/png', 'image/jpeg', 'image/webp', 'application/pdf')),
  size_bytes       INT NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
  original_name    VARCHAR(150) NOT NULL CHECK (char_length(btrim(original_name)) > 0),
  sha256           CHAR(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_message_attachments_message UNIQUE (message_id),
  CONSTRAINT fk_message_attachments_message FOREIGN KEY (message_id, conversation_id)
    REFERENCES messages(id, conversation_id) ON DELETE CASCADE
);

CREATE INDEX idx_message_attachments_conversation ON message_attachments (conversation_id);

-- Archivos por borrar del almacenamiento (lo vacía el worker / npm run storage:purge).
CREATE TABLE storage_deletions (
  storage_key   VARCHAR(300) PRIMARY KEY,
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE FUNCTION enqueue_attachment_deletion() RETURNS trigger AS $$
BEGIN
  INSERT INTO storage_deletions (storage_key) VALUES (OLD.storage_key)
  ON CONFLICT (storage_key) DO NOTHING;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_message_attachments_enqueue_deletion
  AFTER DELETE ON message_attachments
  FOR EACH ROW EXECUTE FUNCTION enqueue_attachment_deletion();
