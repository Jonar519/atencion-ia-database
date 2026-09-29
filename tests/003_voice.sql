-- tests/003_voice.sql
-- Reglas de la voz garantizadas por la base (migraciones 009 y 014): cada
-- regla se ROMPE a propósito y se exige que la base lo rechace.
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

-- Dos clientes, cada uno con su conversación y su llamada.
INSERT INTO customers (id, display_name) VALUES
  ('99999999-0000-4000-8000-0000000000a1', 'Voz A'),
  ('99999999-0000-4000-8000-0000000000a2', 'Voz B');
INSERT INTO conversations (id, customer_id, status, origin_channel) VALUES
  ('99999999-0000-4000-8000-0000000000c1', '99999999-0000-4000-8000-0000000000a1', 'ai_active', 'voice'),
  ('99999999-0000-4000-8000-0000000000c2', '99999999-0000-4000-8000-0000000000a2', 'ai_active', 'voice');
INSERT INTO calls (id, conversation_id, status, consent_given_at, consent_version, stt_provider, tts_provider, retain_until) VALUES
  ('99999999-0000-4000-8000-0000000000d1', '99999999-0000-4000-8000-0000000000c1', 'in_progress', now(), 'voz-v1', 'mock', 'mock', now() + interval '90 days'),
  ('99999999-0000-4000-8000-0000000000d2', '99999999-0000-4000-8000-0000000000c2', 'in_progress', now(), 'voz-v1', 'mock', 'mock', now() + interval '90 days');
INSERT INTO messages (id, conversation_id, sender_type, channel, call_id, content) VALUES
  ('99999999-0000-4000-8000-0000000000e1', '99999999-0000-4000-8000-0000000000c1', 'customer', 'voice',
   '99999999-0000-4000-8000-0000000000d1', 'Quiero saber mi saldo'),
  ('99999999-0000-4000-8000-0000000000e2', '99999999-0000-4000-8000-0000000000c2', 'customer', 'voice',
   '99999999-0000-4000-8000-0000000000d2', 'Mi clave es 4321'),
  ('99999999-0000-4000-8000-0000000000e3', '99999999-0000-4000-8000-0000000000c1', 'customer', 'text',
   NULL, 'Esto lo escribí, no lo dije');

-- Enlace legítimo: segmento de la llamada d1 → turno de la llamada d1.
INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms, message_id) VALUES
  ('99999999-0000-4000-8000-0000000000d1', 0, 'customer', 'Quiero saber mi saldo', 0, 1500,
   '99999999-0000-4000-8000-0000000000e1');
SELECT pg_temp.expect_true('un segmento enlazado a un turno de SU llamada se acepta', true);

SELECT pg_temp.expect_error('un segmento NO puede enlazar el turno de la llamada de OTRO cliente', '23503', $sql$
  INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms, message_id)
  VALUES ('99999999-0000-4000-8000-0000000000d1', 1, 'customer', 'Mi clave es 4321', 1600, 2500,
          '99999999-0000-4000-8000-0000000000e2')
$sql$);

SELECT pg_temp.expect_error('un segmento NO puede enlazar un mensaje de TEXTO (que no es de ninguna llamada)', '23503', $sql$
  INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms, message_id)
  VALUES ('99999999-0000-4000-8000-0000000000d1', 1, 'customer', 'Esto lo escribí', 1600, 2500,
          '99999999-0000-4000-8000-0000000000e3')
$sql$);

SELECT pg_temp.expect_error('dos segmentos no pueden tener el mismo número de orden en una llamada', '23505', $sql$
  INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms)
  VALUES ('99999999-0000-4000-8000-0000000000d1', 0, 'ai', 'Tu saldo es…', 1600, 2500)
$sql$);

SELECT pg_temp.expect_error('no puede haber DOS llamadas activas en la misma conversación', '23505', $sql$
  INSERT INTO calls (conversation_id, status, consent_given_at, consent_version, stt_provider, tts_provider, retain_until)
  VALUES ('99999999-0000-4000-8000-0000000000c1', 'connecting', now(), 'voz-v1', 'mock', 'mock', now() + interval '90 days')
$sql$);

SELECT pg_temp.expect_error('no puede existir una llamada sin consentimiento registrado', '23502', $sql$
  INSERT INTO calls (conversation_id, status, consent_given_at, consent_version, stt_provider, tts_provider, retain_until)
  VALUES ('99999999-0000-4000-8000-0000000000c2', 'ended', NULL, 'voz-v1', 'mock', 'mock', now() + interval '90 days')
$sql$);

SELECT pg_temp.expect_error('el consentimiento no puede ser POSTERIOR al inicio de la llamada', '23514', $sql$
  INSERT INTO calls (conversation_id, status, consent_given_at, consent_version, started_at, ended_at, end_reason,
                     stt_provider, tts_provider, retain_until)
  VALUES ('99999999-0000-4000-8000-0000000000c2', 'ended', now() + interval '1 minute', 'voz-v1', now(), now(),
          'customer_hangup', 'mock', 'mock', now() + interval '90 days')
$sql$);

SELECT pg_temp.expect_error('la transcripción no puede conservarse más de 180 días', '23514', $sql$
  UPDATE calls SET retain_until = started_at + interval '181 days'
  WHERE id = '99999999-0000-4000-8000-0000000000d1'
$sql$);

SELECT pg_temp.expect_error('no se puede purgar una llamada que sigue en curso', '23514', $sql$
  UPDATE calls SET transcript_purged_at = now() WHERE id = '99999999-0000-4000-8000-0000000000d1'
$sql$);

SELECT pg_temp.expect_error('un participante de tipo agente siempre tiene agent_id', '23514', $sql$
  INSERT INTO call_participants (call_id, participant_type, agent_id)
  VALUES ('99999999-0000-4000-8000-0000000000d1', 'agent', NULL)
$sql$);

-- Terminar y purgar d1 (así lo hace el job de retención).
UPDATE calls SET status = 'ended', ended_at = clock_timestamp(), end_reason = 'customer_hangup'
WHERE id = '99999999-0000-4000-8000-0000000000d1';
UPDATE calls SET transcript_purged_at = clock_timestamp() WHERE id = '99999999-0000-4000-8000-0000000000d1';
SELECT pg_temp.expect_true('una llamada terminada se puede purgar', true);

SELECT pg_temp.expect_error('una llamada PURGADA no admite segmentos nuevos', '23514', $sql$
  INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms)
  VALUES ('99999999-0000-4000-8000-0000000000d1', 5, 'customer', 'texto que llegó tarde', 9000, 9500)
$sql$);

-- Borrar el mensaje deja el segmento sin enlace (no lo borra ni rompe la FK compuesta).
DELETE FROM call_transcript_segments WHERE call_id = '99999999-0000-4000-8000-0000000000d1';
INSERT INTO call_transcript_segments (call_id, seq, speaker, text, start_ms, end_ms, message_id) VALUES
  ('99999999-0000-4000-8000-0000000000d2', 0, 'customer', 'Mi clave es 4321', 0, 900,
   '99999999-0000-4000-8000-0000000000e2');
DELETE FROM messages WHERE id = '99999999-0000-4000-8000-0000000000e2';
SELECT pg_temp.expect_true('borrar el turno deja el segmento sin enlace (SET NULL solo de message_id)',
  (SELECT message_id IS NULL AND call_id = '99999999-0000-4000-8000-0000000000d2'
   FROM call_transcript_segments WHERE call_id = '99999999-0000-4000-8000-0000000000d2' AND seq = 0));

\o
SELECT count(*) || ' pruebas de voz pasaron' AS resultado FROM test_results;

ROLLBACK;
