-- tests/007_invitations.sql
-- Reglas de las invitaciones del staff (migración 018), rotas a propósito.
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

-- Un admin que invita y una cuenta en uso (con contraseña).
INSERT INTO staff_users (id, name, email, password_hash, role) VALUES
  ('99999999-0000-4000-8000-0000000000a1', 'Admin Invita', 'invita@test.example', 'x', 'admin'),
  ('99999999-0000-4000-8000-0000000000a2', 'Asesora Activa', 'activa@test.example', 'x', 'agent');

-- Una invitación pendiente: sin contraseña, inactiva.
INSERT INTO staff_users (id, name, email, password_hash, role, is_active, invited_at, invited_by) VALUES
  ('99999999-0000-4000-8000-0000000000a3', 'Asesor Invitado', 'invitado@test.example', NULL, 'agent', false,
   now(), '99999999-0000-4000-8000-0000000000a1');
SELECT pg_temp.expect_true('una invitación pendiente (sin contraseña, inactiva) se acepta', true);

SELECT pg_temp.expect_error('una cuenta sin contraseña que NO es invitación se rechaza', '23514', $sql$
  INSERT INTO staff_users (name, email, password_hash, is_active) VALUES ('Sin Clave', 'sinclave@test.example', NULL, false)
$sql$);

SELECT pg_temp.expect_error('una invitación pendiente no puede estar activa (no entraría con nada)', '23514', $sql$
  UPDATE staff_users SET is_active = true WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

SELECT pg_temp.expect_error('una invitación pendiente no puede tener MFA', '23514', $sql$
  UPDATE staff_users SET mfa_secret_encrypted = 'x', mfa_enabled_at = now() WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

SELECT pg_temp.expect_error('una invitación pendiente no puede tener inicios de sesión', '23514', $sql$
  UPDATE staff_users SET last_login_at = now() WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

SELECT pg_temp.expect_error('una invitación no se marca completada sin contraseña', '23514', $sql$
  UPDATE staff_users SET activated_at = now() WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

SELECT pg_temp.expect_error('una cuenta del seed (no invitada) no puede quedarse sin contraseña', '23514', $sql$
  UPDATE staff_users SET password_hash = NULL, is_active = false WHERE id = '99999999-0000-4000-8000-0000000000a2'
$sql$);

-- Tokens de invitación.
INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
  ('99999999-0000-4000-8000-0000000000a3', 'invitation', repeat('a', 64), now(), now() + interval '72 hours');
SELECT pg_temp.expect_true('una invitación de 72 h para una cuenta pendiente se acepta', true);

SELECT pg_temp.expect_error('una invitación que dura más de 72 h se rechaza', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
    ('99999999-0000-4000-8000-0000000000a3', 'invitation', repeat('b', 64), now(), now() + interval '73 hours')
$sql$);

SELECT pg_temp.expect_error('una segunda invitación vigente para la misma persona se rechaza (solo una)', '23505', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
    ('99999999-0000-4000-8000-0000000000a3', 'invitation', repeat('c', 64), now(), now() + interval '1 hour')
$sql$);

SELECT pg_temp.expect_error('los demás tokens siguen limitados a 30 min (no heredan las 72 h)', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
    ('99999999-0000-4000-8000-0000000000a2', 'password_reset', repeat('d', 64), now(), now() + interval '1 hour')
$sql$);

SELECT pg_temp.expect_error('una invitación para una cuenta que ya está en uso se rechaza', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
    ('99999999-0000-4000-8000-0000000000a2', 'invitation', repeat('e', 64), now(), now() + interval '1 hour')
$sql$);

SELECT pg_temp.expect_error('una cuenta pendiente no puede recibir un enlace de recuperación', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
    ('99999999-0000-4000-8000-0000000000a3', 'password_reset', repeat('f', 64), now(), now() + interval '15 minutes')
$sql$);

SELECT pg_temp.expect_error('no se borra la cuenta de quien invitó (se anonimiza)', '23503', $sql$
  DELETE FROM staff_users WHERE id = '99999999-0000-4000-8000-0000000000a1'
$sql$);

-- Completar la cuenta: contraseña + activa + fecha de activación.
UPDATE staff_users SET password_hash = 'hash', is_active = true, activated_at = now()
  WHERE id = '99999999-0000-4000-8000-0000000000a3';
SELECT pg_temp.expect_true('completar la invitación (contraseña, activa, fecha) se acepta', true);

SELECT pg_temp.expect_error('una cuenta completada no vuelve a quedarse sin contraseña', '23514', $sql$
  UPDATE staff_users SET password_hash = NULL, is_active = false WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

SELECT pg_temp.expect_error('la activación no puede ser anterior a la invitación', '23514', $sql$
  UPDATE staff_users SET activated_at = invited_at - interval '1 day' WHERE id = '99999999-0000-4000-8000-0000000000a3'
$sql$);

-- Cancelar una invitación = borrar la cuenta pendiente: sus tokens se van con ella.
INSERT INTO staff_users (id, name, email, password_hash, role, is_active, invited_at, invited_by) VALUES
  ('99999999-0000-4000-8000-0000000000a4', 'Otro Invitado', 'otro-invitado@test.example', NULL, 'agent', false,
   now(), '99999999-0000-4000-8000-0000000000a1');
INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, created_at, expires_at) VALUES
  ('99999999-0000-4000-8000-0000000000a4', 'invitation', repeat('9', 64), now(), now() + interval '72 hours');
DELETE FROM staff_users WHERE id = '99999999-0000-4000-8000-0000000000a4';
SELECT pg_temp.expect_true('cancelar una invitación borra también su enlace',
  NOT EXISTS (SELECT 1 FROM staff_tokens WHERE token_hash = repeat('9', 64)));

\o
SELECT count(*) || ' pruebas de invitaciones pasaron' AS resultado FROM test_results;

ROLLBACK;
