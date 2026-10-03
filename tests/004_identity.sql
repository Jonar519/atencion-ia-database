-- tests/004_identity.sql
-- Reglas de la identidad del staff (migración 015), rotas a propósito.
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

CREATE FUNCTION pg_temp.h(p TEXT) RETURNS TEXT AS $$ SELECT encode(digest(p, 'sha256'), 'hex') $$ LANGUAGE sql;

INSERT INTO staff_users (id, name, email, password_hash, role) VALUES
  ('99999999-0000-4000-8000-000000000071', 'Identidad Uno', 'identidad1@test.example', 'x', 'agent'),
  ('99999999-0000-4000-8000-000000000072', 'Identidad Dos', 'identidad2@test.example', 'x', 'admin');

-- Tokens de un solo uso ---------------------------------------------------------
INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
VALUES ('99999999-0000-4000-8000-000000000071', 'password_reset', pg_temp.h('uno'), now() + interval '15 minutes');
SELECT pg_temp.expect_true('un token de recuperación válido se acepta', true);

SELECT pg_temp.expect_error('NO puede haber DOS enlaces de recuperación vigentes a la vez', '23505', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
  VALUES ('99999999-0000-4000-8000-000000000071', 'password_reset', pg_temp.h('dos'), now() + interval '15 minutes')
$sql$);

UPDATE staff_tokens SET used_at = now() WHERE token_hash = pg_temp.h('uno');
INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
VALUES ('99999999-0000-4000-8000-000000000071', 'password_reset', pg_temp.h('tres'), now() + interval '15 minutes');
SELECT pg_temp.expect_true('usado el anterior, se puede emitir uno nuevo', true);

SELECT pg_temp.expect_error('un token no puede vivir más de 30 minutos', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
  VALUES ('99999999-0000-4000-8000-000000000072', 'mfa_challenge', pg_temp.h('largo'), now() + interval '2 hours')
$sql$);

SELECT pg_temp.expect_error('el token se guarda como hash, no en claro', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
  VALUES ('99999999-0000-4000-8000-000000000072', 'mfa_challenge', rpad('token-en-claro', 64, 'x'), now() + interval '5 minutes')
$sql$);

SELECT pg_temp.expect_error('un cambio de correo sin el correo nuevo no existe', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at)
  VALUES ('99999999-0000-4000-8000-000000000072', 'email_change', pg_temp.h('sin-correo'), now() + interval '15 minutes')
$sql$);

SELECT pg_temp.expect_error('el correo nuevo debe estar en minúsculas', '23514', $sql$
  INSERT INTO staff_tokens (staff_user_id, purpose, token_hash, expires_at, new_email)
  VALUES ('99999999-0000-4000-8000-000000000072', 'email_change', pg_temp.h('mayus'), now() + interval '15 minutes', 'Nuevo@Test.example')
$sql$);

-- MFA ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('no se puede marcar MFA como activo sin secreto', '23514', $sql$
  UPDATE staff_users SET mfa_enabled_at = now() WHERE id = '99999999-0000-4000-8000-000000000072'
$sql$);

INSERT INTO mfa_backup_codes (staff_user_id, code_hash) VALUES ('99999999-0000-4000-8000-000000000072', pg_temp.h('c1'));
SELECT pg_temp.expect_error('el mismo código de respaldo no se repite para una persona', '23505', $sql$
  INSERT INTO mfa_backup_codes (staff_user_id, code_hash) VALUES ('99999999-0000-4000-8000-000000000072', pg_temp.h('c1'))
$sql$);

-- Anonimización -----------------------------------------------------------------
SELECT pg_temp.expect_error('una cuenta anonimizada no puede seguir activa', '23514', $sql$
  UPDATE staff_users SET deleted_at = now(), email = 'eliminado-71@anonimizado.invalid', phone = NULL
  WHERE id = '99999999-0000-4000-8000-000000000071'
$sql$);

SELECT pg_temp.expect_error('una cuenta anonimizada no conserva su correo real', '23514', $sql$
  UPDATE staff_users SET deleted_at = now(), is_active = false
  WHERE id = '99999999-0000-4000-8000-000000000071'
$sql$);

UPDATE staff_users SET phone = '+57 300 000 0000', avatar_storage_key = 'avatars/x.webp'
WHERE id = '99999999-0000-4000-8000-000000000071';
SELECT pg_temp.expect_error('una cuenta anonimizada no conserva teléfono ni avatar', '23514', $sql$
  UPDATE staff_users SET deleted_at = now(), is_active = false, email = 'eliminado-71@anonimizado.invalid'
  WHERE id = '99999999-0000-4000-8000-000000000071'
$sql$);

UPDATE staff_users SET deleted_at = now(), is_active = false, email = 'eliminado-71@anonimizado.invalid',
  phone = NULL, avatar_storage_key = NULL
WHERE id = '99999999-0000-4000-8000-000000000071';
SELECT pg_temp.expect_true('anonimizada correctamente (sin datos personales, inactiva)', true);

SELECT pg_temp.expect_error('el tema solo admite system, light o dark', '23514', $sql$
  UPDATE staff_users SET theme = 'rosa' WHERE id = '99999999-0000-4000-8000-000000000072'
$sql$);

SELECT pg_temp.expect_error('un teléfono con letras se rechaza', '23514', $sql$
  UPDATE staff_users SET phone = 'llámame' WHERE id = '99999999-0000-4000-8000-000000000072'
$sql$);

-- Sesiones: nunca la IP completa -------------------------------------------------
SELECT pg_temp.expect_error('la sesión NO guarda la IPv4 completa (solo x.y.z.0)', '23514', $sql$
  INSERT INTO refresh_tokens (staff_user_id, family_id, token_hash, expires_at, ip_address)
  VALUES ('99999999-0000-4000-8000-000000000072', gen_random_uuid(), pg_temp.h('s1'), now() + interval '1 day', '190.24.13.77')
$sql$);

INSERT INTO refresh_tokens (staff_user_id, family_id, token_hash, expires_at, ip_address, location_label)
VALUES ('99999999-0000-4000-8000-000000000072', gen_random_uuid(), pg_temp.h('s2'), now() + interval '1 day',
        '190.24.13.0', 'Bogotá, Colombia (aproximada)');
SELECT pg_temp.expect_true('la sesión guarda la IP truncada y la ubicación aproximada', true);

SELECT pg_temp.expect_error('un motivo de revocación desconocido se rechaza', '23514', $sql$
  UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = 'porque_si' WHERE token_hash = pg_temp.h('s2')
$sql$);

\o
SELECT count(*) || ' pruebas de identidad pasaron' AS resultado FROM test_results;

ROLLBACK;
