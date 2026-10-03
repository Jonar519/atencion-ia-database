-- tests/005_canned_responses.sql
-- Reglas de las respuestas predefinidas (migración 016), rotas a propósito.
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

INSERT INTO staff_users (id, name, email, password_hash, role) VALUES
  ('99999999-0000-4000-8000-000000000081', 'Admin Respuestas', 'respuestas@test.example', 'x', 'admin'),
  ('99999999-0000-4000-8000-000000000082', 'Admin Editor', 'editor@test.example', 'x', 'admin');

INSERT INTO canned_responses (id, title, body, shortcut, created_by, updated_by) VALUES
  ('99999999-0000-4000-8000-000000000091', 'Saludo', 'Hola {cliente}, soy {asesor}. ¿En qué te ayudo?', 'saludo',
   '99999999-0000-4000-8000-000000000081', '99999999-0000-4000-8000-000000000082');
SELECT pg_temp.expect_true('una respuesta válida con marcadores se acepta', true);

SELECT pg_temp.expect_error('un título repetido (sin distinguir mayúsculas ni espacios) se rechaza', '23505', $sql$
  INSERT INTO canned_responses (title, body) VALUES ('  SALUDO ', 'Otro texto')
$sql$);

SELECT pg_temp.expect_error('un atajo repetido se rechaza', '23505', $sql$
  INSERT INTO canned_responses (title, body, shortcut) VALUES ('Saludo formal', 'Buen día', 'saludo')
$sql$);

SELECT pg_temp.expect_error('un atajo con espacios o mayúsculas se rechaza', '23514', $sql$
  INSERT INTO canned_responses (title, body, shortcut) VALUES ('Cierre', 'Gracias', 'Cierre Rápido')
$sql$);

SELECT pg_temp.expect_error('un cuerpo vacío (solo espacios) se rechaza', '23514', $sql$
  INSERT INTO canned_responses (title, body) VALUES ('Vacía', '   ')
$sql$);

SELECT pg_temp.expect_error('un cuerpo de más de 2000 caracteres se rechaza', '23514', $sql$
  INSERT INTO canned_responses (title, body) VALUES ('Larga', repeat('a', 2001))
$sql$);

SELECT pg_temp.expect_error('un título de un solo carácter se rechaza', '23514', $sql$
  INSERT INTO canned_responses (title, body) VALUES (' x ', 'Texto')
$sql$);

-- Autor y editor son cuentas DISTINTAS: cada FK se prueba por separado.
SELECT pg_temp.expect_error('no se borra la cuenta de quien la creó (se anonimiza)', '23503', $sql$
  DELETE FROM staff_users WHERE id = '99999999-0000-4000-8000-000000000081'
$sql$);

SELECT pg_temp.expect_error('no se borra la cuenta de quien la editó por última vez', '23503', $sql$
  DELETE FROM staff_users WHERE id = '99999999-0000-4000-8000-000000000082'
$sql$);

UPDATE canned_responses SET updated_at = now() - interval '1 day' WHERE id = '99999999-0000-4000-8000-000000000091';
UPDATE canned_responses SET body = 'Hola {cliente}' WHERE id = '99999999-0000-4000-8000-000000000091';
SELECT pg_temp.expect_true('editar actualiza updated_at (trigger)',
  (SELECT updated_at > now() - interval '1 minute' FROM canned_responses WHERE id = '99999999-0000-4000-8000-000000000091'));

\o
SELECT count(*) || ' pruebas de respuestas predefinidas pasaron' AS resultado FROM test_results;

ROLLBACK;
