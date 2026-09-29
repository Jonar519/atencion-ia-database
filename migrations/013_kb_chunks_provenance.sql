-- 013_kb_chunks_provenance.sql
-- Aislamiento del RAG garantizado por la BASE, no solo por el backend.
--
-- Regla (docs/domain-model.md §3.6): kb_chunks contiene SOLO texto de la base
-- de conocimiento. Hasta ahora eso dependía de que el código nunca escribiera
-- otra cosa. Este trigger lo hace imposible: cada fragmento que se inserta o
-- modifica debe ser un pedazo LITERAL del cuerpo de su artículo, de la versión
-- vigente del artículo. Así, ni un bug ni un worker comprometido pueden meter
-- el mensaje de un cliente en el índice del RAG (donde otro cliente podría
-- recuperarlo como "contexto").
--
-- El indexador (backend: src/modules/rag/chunking.ts) corta el cuerpo en
-- fragmentos que son subcadenas exactas; el título se antepone solo al texto
-- que se envía al modelo de embeddings, no al contenido guardado.

CREATE OR REPLACE FUNCTION kb_chunks_check_provenance()
RETURNS trigger AS $$
DECLARE
  article_body    TEXT;
  article_version INT;
BEGIN
  -- FOR SHARE: si el artículo se está editando en otra transacción, se espera
  -- a que termine y se valida contra la versión confirmada.
  SELECT body, version INTO article_body, article_version
  FROM kb_articles WHERE id = NEW.article_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'kb_chunks: el artículo % no existe', NEW.article_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF NEW.article_version <> article_version THEN
    RAISE EXCEPTION 'kb_chunks: el fragmento es de la versión % pero el artículo está en la versión %',
      NEW.article_version, article_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF strpos(article_body, NEW.content) = 0 THEN
    RAISE EXCEPTION 'kb_chunks: el contenido del fragmento no proviene del artículo %', NEW.article_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- El hash debe corresponder al contenido (lo usa el indexador para saber
  -- qué fragmentos no cambiaron).
  IF NEW.content_sha256 <> encode(digest(NEW.content, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'kb_chunks: content_sha256 no coincide con el contenido'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kb_chunks_provenance
  BEFORE INSERT OR UPDATE OF content, article_id, article_version, content_sha256 ON kb_chunks
  FOR EACH ROW EXECUTE FUNCTION kb_chunks_check_provenance();
