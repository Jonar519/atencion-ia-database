-- tests/001_constraints.sql
-- Pruebas de las reglas que hace cumplir el esquema (docs/domain-model.md §4).
--
-- Todo corre en una transacción que termina en ROLLBACK: no deja datos y se
-- puede ejecutar sobre una base con o sin seed. Crea sus propios datos con
-- IDs 9999…, que no chocan con los del seed.
--
-- Si una regla no se cumple, el script termina con error (código de salida
-- distinto de 0) indicando qué prueba falló. Si todo pasa, lista las pruebas.
--
-- Ejecutar con scripts\test.bat (cmd.exe) o scripts/test.sh (CI).

\set ON_ERROR_STOP 1
SET client_min_messages = warning;
-- Las llamadas a expect_* no imprimen nada útil: salida descartada hasta el resumen.
\o /dev/null

BEGIN;

CREATE TEMP TABLE test_results (n SERIAL, name TEXT NOT NULL) ON COMMIT DROP;

-- Ejecuta p_sql y exige que falle con el SQLSTATE indicado.
-- (El bloque BEGIN/EXCEPTION crea un subtransacción: el intento fallido se
-- deshace sin abortar la transacción de las pruebas.)
CREATE FUNCTION pg_temp.expect_error(p_name TEXT, p_state TEXT, p_sql TEXT) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = p_state THEN
      INSERT INTO test_results (name) VALUES (p_name);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FALLA [%]: se esperaba SQLSTATE % y llegó % (%)', p_name, p_state, SQLSTATE, SQLERRM;
  END;
  RAISE EXCEPTION 'FALLA [%]: se esperaba error % y la sentencia se ejecutó', p_name, p_state;
END;
$$ LANGUAGE plpgsql;

-- Exige que p_cond sea verdadera.
CREATE FUNCTION pg_temp.expect_true(p_name TEXT, p_cond BOOLEAN) RETURNS void AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FALLA [%]: la condición no se cumple', p_name;
  END IF;
  INSERT INTO test_results (name) VALUES (p_name);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Datos propios de la prueba
-- ---------------------------------------------------------------------------
INSERT INTO staff_users (id, name, email, password_hash, role) VALUES
  ('99999999-0000-4000-8000-00000000a001', 'Agente Prueba', 'agente.prueba@test.example', 'x', 'agent');
INSERT INTO customers (id, display_name) VALUES
  ('99999999-0000-4000-8000-00000000b001', 'Cliente Prueba');
INSERT INTO conversations (id, customer_id, origin_channel) VALUES
  ('99999999-0000-4000-8000-00000000c001', '99999999-0000-4000-8000-00000000b001', 'text'),
  ('99999999-0000-4000-8000-00000000c002', '99999999-0000-4000-8000-00000000b001', 'voice');
INSERT INTO calls (id, conversation_id, consent_given_at, consent_version, started_at, stt_provider, tts_provider, retain_until) VALUES
  ('99999999-0000-4000-8000-00000000d001', '99999999-0000-4000-8000-00000000c002',
   now(), 'v1', now(), 'mock', 'mock', now() + interval '30 days');
INSERT INTO messages (id, conversation_id, sender_type, content, client_msg_id) VALUES
  ('99999999-0000-4000-8000-00000000e001', '99999999-0000-4000-8000-00000000c001', 'customer', 'hola',
   '99999999-0000-4000-8000-00000000f001'),
  ('99999999-0000-4000-8000-00000000e002', '99999999-0000-4000-8000-00000000c002', 'customer', 'hola',
   NULL);

-- ---------------------------------------------------------------------------
-- Escalamientos
-- ---------------------------------------------------------------------------
INSERT INTO escalations (conversation_id, trigger_source, reason)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'rule', 'possible_fraud');

SELECT pg_temp.expect_error('un solo escalamiento abierto por conversación', '23505', $sql$
  INSERT INTO escalations (conversation_id, trigger_source, reason)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'ai_signal', 'angry_customer')
$sql$);

-- ON CONFLICT DO NOTHING (lo que usa el backend) no falla ni duplica.
INSERT INTO escalations (conversation_id, trigger_source, reason)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'ai_signal', 'angry_customer')
  ON CONFLICT (conversation_id) WHERE status IN ('open', 'assigned') DO NOTHING;
SELECT pg_temp.expect_true('ON CONFLICT DO NOTHING no duplica el escalamiento abierto',
  (SELECT count(*) FROM escalations WHERE conversation_id = '99999999-0000-4000-8000-00000000c001') = 1);

-- Resuelto el anterior, se puede volver a escalar.
UPDATE escalations SET status = 'resolved', resolved_at = now()
  WHERE conversation_id = '99999999-0000-4000-8000-00000000c001';
INSERT INTO escalations (conversation_id, trigger_source, reason)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'customer_request', 'human_requested');
SELECT pg_temp.expect_true('tras resolver, la conversación puede escalar de nuevo',
  (SELECT count(*) FROM escalations WHERE conversation_id = '99999999-0000-4000-8000-00000000c001') = 2);

SELECT pg_temp.expect_error('escalamiento asignado exige agente', '23514', $sql$
  UPDATE escalations SET status = 'assigned'
  WHERE conversation_id = '99999999-0000-4000-8000-00000000c001' AND status = 'open'
$sql$);

SELECT pg_temp.expect_error('el mensaje que dispara un escalamiento es de la misma conversación', '23503', $sql$
  INSERT INTO escalations (conversation_id, triggering_message_id, trigger_source, reason)
  VALUES ('99999999-0000-4000-8000-00000000c002', '99999999-0000-4000-8000-00000000e001', 'rule', 'complaint')
$sql$);

SELECT pg_temp.expect_error('signal debe ser un objeto JSON', '23514', $sql$
  INSERT INTO escalations (conversation_id, trigger_source, reason, signal)
  VALUES ('99999999-0000-4000-8000-00000000c002', 'rule', 'complaint', '[1, 2]')
$sql$);

-- ---------------------------------------------------------------------------
-- Mensajes
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('client_msg_id no se duplica en la conversación (reenvío tras reconectar)', '23505', $sql$
  INSERT INTO messages (conversation_id, sender_type, content, client_msg_id)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'customer', 'hola otra vez', '99999999-0000-4000-8000-00000000f001')
$sql$);

SELECT pg_temp.expect_error('mensaje de agente exige agente', '23514', $sql$
  INSERT INTO messages (conversation_id, sender_type, content)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'agent', 'soy un agente sin id')
$sql$);

SELECT pg_temp.expect_error('mensaje de la IA no puede tener agente', '23514', $sql$
  INSERT INTO messages (conversation_id, sender_type, sender_agent_id, content)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'ai', '99999999-0000-4000-8000-00000000a001', 'x')
$sql$);

SELECT pg_temp.expect_error('turno de voz exige llamada', '23514', $sql$
  INSERT INTO messages (conversation_id, sender_type, channel, content)
  VALUES ('99999999-0000-4000-8000-00000000c002', 'customer', 'voice', 'transcrito')
$sql$);

SELECT pg_temp.expect_error('turno de voz con llamada de OTRA conversación', '23503', $sql$
  INSERT INTO messages (conversation_id, sender_type, channel, call_id, content)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'customer', 'voice', '99999999-0000-4000-8000-00000000d001', 'x')
$sql$);

INSERT INTO messages (conversation_id, sender_type, channel, call_id, content)
  VALUES ('99999999-0000-4000-8000-00000000c002', 'customer', 'voice', '99999999-0000-4000-8000-00000000d001', 'transcrito');
SELECT pg_temp.expect_true('turno de voz con su llamada se acepta', true);

SELECT pg_temp.expect_error('el análisis de intención es solo para mensajes del cliente', '23514', $sql$
  INSERT INTO messages (conversation_id, sender_type, content, intent)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'ai', 'respuesta', 'complaint')
$sql$);

SELECT pg_temp.expect_error('mensaje vacío', '23514', $sql$
  INSERT INTO messages (conversation_id, sender_type, content)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'customer', '   ')
$sql$);

-- Dos mensajes en la misma transacción no empatan en created_at (clock_timestamp).
INSERT INTO messages (id, conversation_id, sender_type, content) VALUES
  ('99999999-0000-4000-8000-00000000e011', '99999999-0000-4000-8000-00000000c001', 'customer', 'pregunta');
INSERT INTO messages (id, conversation_id, sender_type, content) VALUES
  ('99999999-0000-4000-8000-00000000e012', '99999999-0000-4000-8000-00000000c001', 'ai', 'respuesta');
SELECT pg_temp.expect_true('mensajes de la misma transacción quedan en orden',
  (SELECT created_at FROM messages WHERE id = '99999999-0000-4000-8000-00000000e011')
  < (SELECT created_at FROM messages WHERE id = '99999999-0000-4000-8000-00000000e012'));

-- ---------------------------------------------------------------------------
-- Llamadas
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('no hay llamada sin consentimiento', '23502', $sql$
  INSERT INTO calls (conversation_id, consent_version, stt_provider, tts_provider, retain_until)
  VALUES ('99999999-0000-4000-8000-00000000c001', 'v1', 'mock', 'mock', now() + interval '30 days')
$sql$);

SELECT pg_temp.expect_error('una sola llamada activa por conversación', '23505', $sql$
  INSERT INTO calls (conversation_id, consent_given_at, consent_version, stt_provider, tts_provider, retain_until)
  VALUES ('99999999-0000-4000-8000-00000000c002', now(), 'v1', 'mock', 'mock', now() + interval '30 days')
$sql$);

SELECT pg_temp.expect_error('llamada terminada exige fecha de fin', '23514', $sql$
  UPDATE calls SET status = 'ended' WHERE id = '99999999-0000-4000-8000-00000000d001'
$sql$);

UPDATE calls SET status = 'ended',
                 answered_at = started_at + interval '5 seconds',
                 ended_at = started_at + interval '125 seconds',
                 end_reason = 'customer_hangup'
  WHERE id = '99999999-0000-4000-8000-00000000d001';
SELECT pg_temp.expect_true('duration_seconds se calcula desde answered_at y ended_at',
  (SELECT duration_seconds FROM calls WHERE id = '99999999-0000-4000-8000-00000000d001') = 120);

SELECT pg_temp.expect_error('duration_seconds no se puede escribir', '428C9', $sql$
  UPDATE calls SET duration_seconds = 5 WHERE id = '99999999-0000-4000-8000-00000000d001'
$sql$);

SELECT pg_temp.expect_error('participante agente exige agente', '23514', $sql$
  INSERT INTO call_participants (call_id, participant_type)
  VALUES ('99999999-0000-4000-8000-00000000d001', 'agent')
$sql$);

INSERT INTO call_participants (call_id, participant_type, agent_id)
  VALUES ('99999999-0000-4000-8000-00000000d001', 'agent', '99999999-0000-4000-8000-00000000a001');
SELECT pg_temp.expect_error('un agente no se une dos veces a la misma llamada a la vez', '23505', $sql$
  INSERT INTO call_participants (call_id, participant_type, agent_id)
  VALUES ('99999999-0000-4000-8000-00000000d001', 'agent', '99999999-0000-4000-8000-00000000a001')
$sql$);

SELECT pg_temp.expect_error('segmentos de transcripción sin seq repetido', '23505', $sql$
  INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms) VALUES
    ('99999999-0000-4000-8000-00000000d001', 0, 'customer', 'uno', 0, 100),
    ('99999999-0000-4000-8000-00000000d001', 0, 'customer', 'dos', 100, 200)
$sql$);

-- ---------------------------------------------------------------------------
-- Conversaciones
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('conversación atendida exige agente', '23514', $sql$
  UPDATE conversations SET status = 'agent_active' WHERE id = '99999999-0000-4000-8000-00000000c001'
$sql$);

SELECT pg_temp.expect_error('conversación cerrada exige fecha y motivo', '23514', $sql$
  UPDATE conversations SET status = 'closed' WHERE id = '99999999-0000-4000-8000-00000000c001'
$sql$);

SELECT pg_temp.expect_error('prioridad fuera de rango', '23514', $sql$
  UPDATE conversations SET priority = 101 WHERE id = '99999999-0000-4000-8000-00000000c001'
$sql$);

UPDATE conversations SET status = 'agent_active', assigned_agent_id = '99999999-0000-4000-8000-00000000a001'
  WHERE id = '99999999-0000-4000-8000-00000000c001';
SELECT pg_temp.expect_error('no se borra un agente con conversaciones asignadas (se desactiva)', '23503', $sql$
  DELETE FROM staff_users WHERE id = '99999999-0000-4000-8000-00000000a001'
$sql$);

-- ---------------------------------------------------------------------------
-- Identidad
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('correo del staff siempre en minúsculas', '23514', $sql$
  INSERT INTO staff_users (name, email, password_hash) VALUES ('X', 'Mayus@Test.example', 'x')
$sql$);

SELECT pg_temp.expect_error('correo del staff único', '23505', $sql$
  INSERT INTO staff_users (name, email, password_hash) VALUES ('X', 'agente.prueba@test.example', 'x')
$sql$);

SELECT pg_temp.expect_error('refresh token solo como hash hexadecimal', '23514', $sql$
  INSERT INTO refresh_tokens (staff_user_id, family_id, token_hash, expires_at)
  VALUES ('99999999-0000-4000-8000-00000000a001', gen_random_uuid(), 'token-en-claro', now() + interval '7 days')
$sql$);

SELECT pg_temp.expect_error('refresh token revocado exige motivo', '23514', $sql$
  INSERT INTO refresh_tokens (staff_user_id, family_id, token_hash, expires_at, revoked_at)
  VALUES ('99999999-0000-4000-8000-00000000a001', gen_random_uuid(), repeat('a', 64), now() + interval '7 days', now())
$sql$);

-- Dos clientes anónimos (sin correo) conviven; dos con el mismo correo no.
INSERT INTO customers (display_name) VALUES (NULL), (NULL);
INSERT INTO customers (email) VALUES ('mismo@test.example');
SELECT pg_temp.expect_error('correo de cliente único cuando existe', '23505', $sql$
  INSERT INTO customers (email) VALUES ('mismo@test.example')
$sql$);

-- ---------------------------------------------------------------------------
-- Base de conocimiento
-- ---------------------------------------------------------------------------
INSERT INTO kb_articles (id, slug, title, body, category, status, published_at) VALUES
  ('99999999-0000-4000-8000-0000000000f1', 'articulo-prueba', 'Prueba', 'Cuerpo', 'pruebas', 'published', now());

INSERT INTO kb_chunks (article_id, article_version, chunk_index, content, content_sha256, embedding, embedding_model)
  VALUES ('99999999-0000-4000-8000-0000000000f1', 1, 0, 'Cuerpo', encode(digest('Cuerpo', 'sha256'), 'hex'),
          array_fill(0.1::real, ARRAY[1024])::vector, 'mock-embed-v1');

SELECT pg_temp.expect_error('no se duplican embeddings del mismo fragmento y modelo', '23505', $sql$
  INSERT INTO kb_chunks (article_id, article_version, chunk_index, content, content_sha256, embedding, embedding_model)
  VALUES ('99999999-0000-4000-8000-0000000000f1', 1, 0, 'Cuerpo', encode(digest('Cuerpo', 'sha256'), 'hex'),
          array_fill(0.2::real, ARRAY[1024])::vector, 'mock-embed-v1')
$sql$);

SELECT pg_temp.expect_error('embedding con dimensión incorrecta', '22000', $sql$
  INSERT INTO kb_chunks (article_id, article_version, chunk_index, content, content_sha256, embedding, embedding_model)
  VALUES ('99999999-0000-4000-8000-0000000000f1', 1, 1, 'Cuerpo', encode(digest('Cuerpo', 'sha256'), 'hex'),
          array_fill(0.2::real, ARRAY[3])::vector, 'mock-embed-v1')
$sql$);

SELECT pg_temp.expect_error('artículo publicado exige fecha de publicación', '23514', $sql$
  INSERT INTO kb_articles (slug, title, body, category, status) VALUES ('otro', 'T', 'B', 'c', 'published')
$sql$);

SELECT pg_temp.expect_error('slug en formato kebab-case', '23514', $sql$
  INSERT INTO kb_articles (slug, title, body, category) VALUES ('Con Espacios', 'T', 'B', 'c')
$sql$);

-- ---------------------------------------------------------------------------
-- updated_at automático
-- ---------------------------------------------------------------------------
UPDATE conversations SET updated_at = now() - interval '1 day' WHERE id = '99999999-0000-4000-8000-00000000c002';
-- El trigger lo sobreescribe con now() aunque el UPDATE intente otro valor.
SELECT pg_temp.expect_true('el trigger mantiene updated_at',
  (SELECT updated_at FROM conversations WHERE id = '99999999-0000-4000-8000-00000000c002') = now());

-- ---------------------------------------------------------------------------
-- Borrado de un cliente (derecho de supresión) arrastra todo lo suyo
-- ---------------------------------------------------------------------------
DELETE FROM customers WHERE id = '99999999-0000-4000-8000-00000000b001';
SELECT pg_temp.expect_true('borrar un cliente borra sus conversaciones, mensajes, llamadas y escalamientos',
  NOT EXISTS (SELECT 1 FROM conversations WHERE customer_id = '99999999-0000-4000-8000-00000000b001')
  AND NOT EXISTS (SELECT 1 FROM messages WHERE conversation_id IN ('99999999-0000-4000-8000-00000000c001', '99999999-0000-4000-8000-00000000c002'))
  AND NOT EXISTS (SELECT 1 FROM calls WHERE id = '99999999-0000-4000-8000-00000000d001')
  AND NOT EXISTS (SELECT 1 FROM escalations WHERE conversation_id = '99999999-0000-4000-8000-00000000c001'));

-- ---------------------------------------------------------------------------
\o
\echo
\echo Pruebas superadas:
SELECT n AS "#", name AS prueba FROM test_results ORDER BY n;

ROLLBACK;
