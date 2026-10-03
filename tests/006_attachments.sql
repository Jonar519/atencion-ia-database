-- tests/006_attachments.sql
-- Reglas de los adjuntos del chat (migración 017), rotas a propósito.
-- Mismo mecanismo que 001: transacción con ROLLBACK, falla con código ≠ 0.

\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null

BEGIN;

CREATE TEMP TABLE test_results (n SERIAL, name TEXT NOT NULL) ON COMMIT DROP;

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

CREATE FUNCTION pg_temp.expect_true(p_name TEXT, p_cond BOOLEAN) RETURNS void AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FALLA [%]: la condición no se cumple', p_name;
  END IF;
  INSERT INTO test_results (name) VALUES (p_name);
END;
$$ LANGUAGE plpgsql;

-- Dos conversaciones de clientes distintos, con un mensaje cada una.
INSERT INTO customers (id, display_name) VALUES
  ('99999999-0000-4000-8000-0000000000a1', 'Adjuntos Uno'),
  ('99999999-0000-4000-8000-0000000000a2', 'Adjuntos Dos');
INSERT INTO conversations (id, customer_id, origin_channel) VALUES
  ('99999999-0000-4000-8000-0000000000b1', '99999999-0000-4000-8000-0000000000a1', 'text'),
  ('99999999-0000-4000-8000-0000000000b2', '99999999-0000-4000-8000-0000000000a2', 'text');
INSERT INTO messages (id, conversation_id, sender_type, content) VALUES
  ('99999999-0000-4000-8000-0000000000c1', '99999999-0000-4000-8000-0000000000b1', 'customer', '📎 Archivo adjunto'),
  ('99999999-0000-4000-8000-0000000000c2', '99999999-0000-4000-8000-0000000000b2', 'customer', '📎 Archivo adjunto'),
  ('99999999-0000-4000-8000-0000000000c3', '99999999-0000-4000-8000-0000000000b1', 'customer', 'otro');

CREATE FUNCTION pg_temp.att(p_msg TEXT, p_conv TEXT, p_key TEXT, p_type TEXT, p_size INT, p_name TEXT) RETURNS void AS $$
  INSERT INTO message_attachments (message_id, conversation_id, storage_key, content_type, size_bytes, original_name, sha256)
  VALUES (p_msg::uuid, p_conv::uuid, p_key, p_type, p_size, p_name, repeat('a', 64))
$$ LANGUAGE sql;

SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c1', '99999999-0000-4000-8000-0000000000b1',
  'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000001.pdf', 'application/pdf', 1024, 'factura.pdf');
SELECT pg_temp.expect_true('un PDF válido de un mensaje de SU conversación se acepta', true);

SELECT pg_temp.expect_error('un adjunto NO puede pegarse a un mensaje de OTRA conversación', '23503', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c2', '99999999-0000-4000-8000-0000000000b1',
    'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000002.pdf', 'application/pdf', 10, 'x.pdf')
$sql$);

SELECT pg_temp.expect_error('un segundo adjunto en el mismo mensaje se rechaza', '23505', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c1', '99999999-0000-4000-8000-0000000000b1',
    'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000003.png', 'image/png', 10, 'y.png')
$sql$);

SELECT pg_temp.expect_error('tipos no permitidos (SVG, HTML) se rechazan', '23514', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c3', '99999999-0000-4000-8000-0000000000b1',
    'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000004.png', 'image/svg+xml', 10, 'z.svg')
$sql$);

SELECT pg_temp.expect_error('más de 5 MB se rechaza', '23514', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c3', '99999999-0000-4000-8000-0000000000b1',
    'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000005.pdf', 'application/pdf', 5242881, 'grande.pdf')
$sql$);

SELECT pg_temp.expect_error('una clave de almacenamiento con ../ (o fuera de attachments/) se rechaza', '23514', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c3', '99999999-0000-4000-8000-0000000000b1',
    'attachments/../avatars/x.png', 'image/png', 10, 'x.png')
$sql$);

SELECT pg_temp.expect_error('un nombre vacío se rechaza', '23514', $sql$
  SELECT pg_temp.att('99999999-0000-4000-8000-0000000000c3', '99999999-0000-4000-8000-0000000000b1',
    'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000006.png', 'image/png', 10, '   ')
$sql$);

-- Retención: borrar al cliente borra el adjunto en cascada Y encola su archivo.
DELETE FROM customers WHERE id = '99999999-0000-4000-8000-0000000000a1';
SELECT pg_temp.expect_true('borrar al cliente borra sus adjuntos (cascada)',
  NOT EXISTS (SELECT 1 FROM message_attachments WHERE conversation_id = '99999999-0000-4000-8000-0000000000b1'));
SELECT pg_temp.expect_true('y deja su archivo en la cola de borrado del almacenamiento',
  EXISTS (SELECT 1 FROM storage_deletions
          WHERE storage_key = 'attachments/99999999-0000-4000-8000-0000000000b1/11111111-0000-4000-8000-000000000001.pdf'));

\o
SELECT count(*) || ' pruebas de adjuntos pasaron' AS resultado FROM test_results;

ROLLBACK;
