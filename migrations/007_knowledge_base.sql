-- 007_knowledge_base.sql
-- Base de conocimiento (artículos/FAQs) y sus fragmentos con embedding.
--
-- AISLAMIENTO DEL RAG: kb_chunks contiene SOLO contenido de kb_articles. Los
-- mensajes de los clientes nunca se escriben aquí, así que el texto de un
-- cliente no puede aparecer como "contexto" en la respuesta a otro cliente.

CREATE TABLE kb_articles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          VARCHAR(120) NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title         VARCHAR(200) NOT NULL CHECK (length(btrim(title)) > 0),
  body          TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 50000),
  category      VARCHAR(60) NOT NULL CHECK (length(btrim(category)) > 0),
  tags          TEXT[] NOT NULL DEFAULT '{}',
  status        kb_article_status NOT NULL DEFAULT 'draft',
  -- Sube en cada edición de title/body: los fragmentos indexados guardan con
  -- qué versión se generaron, así se detecta un índice desactualizado.
  version       INT NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_by    UUID REFERENCES staff_users(id) ON DELETE SET NULL,
  updated_by    UUID REFERENCES staff_users(id) ON DELETE SET NULL,
  published_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_kb_articles_slug UNIQUE (slug),
  CONSTRAINT chk_kb_articles_published CHECK (status <> 'published' OR published_at IS NOT NULL)
);

-- Listado del panel de admin por estado y categoría.
CREATE INDEX idx_kb_articles_status_category ON kb_articles (status, category, updated_at DESC);
CREATE INDEX idx_kb_articles_tags ON kb_articles USING gin (tags);
CREATE INDEX idx_kb_articles_created_by ON kb_articles (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX idx_kb_articles_updated_by ON kb_articles (updated_by) WHERE updated_by IS NOT NULL;

CREATE TRIGGER trg_kb_articles_updated_at
  BEFORE UPDATE ON kb_articles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Fragmentos con embedding. Dimensión 1024 (la del proveedor de embeddings
-- recomendado; el proveedor mock genera vectores de la misma dimensión).
-- Cambiar de dimensión = migración nueva + re-indexar.
CREATE TABLE kb_chunks (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id       UUID NOT NULL REFERENCES kb_articles(id) ON DELETE CASCADE,
  article_version  INT NOT NULL CHECK (article_version >= 1),
  chunk_index      INT NOT NULL CHECK (chunk_index >= 0),
  content          TEXT NOT NULL CHECK (length(btrim(content)) > 0),
  content_sha256   CHAR(64) NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  embedding        vector(1024) NOT NULL,
  embedding_model  VARCHAR(80) NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Re-indexar un artículo reemplaza sus fragmentos, nunca los duplica.
  -- (Su columna inicial, article_id, también sirve de índice para la FK.)
  CONSTRAINT uq_kb_chunks_article_chunk_model UNIQUE (article_id, chunk_index, embedding_model)
);

-- Búsqueda semántica por similitud coseno.
CREATE INDEX idx_kb_chunks_embedding ON kb_chunks USING hnsw (embedding vector_cosine_ops);
