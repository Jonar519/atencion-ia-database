-- 001_extensions.sql
-- Extensiones necesarias para el proyecto.
-- pgcrypto: generación de UUIDs (gen_random_uuid()) y, en los tests del
--           esquema, verificación de los hashes bcrypt del seed.
-- vector (pgvector): embeddings de la base de conocimiento para RAG.
--
-- En AWS RDS, pgvector está disponible de forma nativa desde Postgres 15.3;
-- el usuario maestro debe crear las extensiones antes de la primera migración.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
