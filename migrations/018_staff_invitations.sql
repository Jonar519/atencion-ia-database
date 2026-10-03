-- 018_staff_invitations.sql
-- Bloque F2: alta de asesores SOLO por invitación. No hay registro público ni
-- contraseñas fijadas por un admin: un admin invita (nombre, correo, rol), la
-- persona recibe un enlace de un solo uso y elige SU contraseña.
--   - Una cuenta INVITADA (pendiente) existe sin contraseña: no puede entrar,
--     no tiene MFA ni inicios de sesión, y no está activa.
--   - Su enlace es un token de staff_tokens con propósito 'invitation' que vive
--     como máximo 72 h (los demás tokens siguen limitados a 30 min).
--   - Una cuenta pendiente solo puede tener tokens de invitación, y un token
--     de invitación solo puede ser de una cuenta pendiente (trigger).

ALTER TABLE staff_users
  ALTER COLUMN password_hash DROP NOT NULL,
  -- Cuándo y quién invitó. NULL en las cuentas anteriores a las invitaciones (seed).
  ADD COLUMN invited_at TIMESTAMPTZ,
  -- RESTRICT, como el resto del historial: las cuentas se anonimizan, no se borran.
  ADD COLUMN invited_by UUID REFERENCES staff_users(id) ON DELETE RESTRICT,
  -- Cuándo la persona completó su cuenta (eligió su contraseña).
  ADD COLUMN activated_at TIMESTAMPTZ;

-- Sin contraseña ⇒ invitación pendiente: no entra, no tiene MFA ni historial de login, no está anonimizada.
ALTER TABLE staff_users
  ADD CONSTRAINT chk_staff_users_pending CHECK (
    password_hash IS NOT NULL OR (
      invited_at IS NOT NULL
      AND NOT is_active
      AND activated_at IS NULL
      AND last_login_at IS NULL
      AND mfa_secret_encrypted IS NULL
      AND mfa_enabled_at IS NULL
      AND deleted_at IS NULL
    )
  );

-- Activada ⇒ fue invitada y ya tiene contraseña (después de la invitación).
ALTER TABLE staff_users
  ADD CONSTRAINT chk_staff_users_activated CHECK (
    activated_at IS NULL OR (invited_at IS NOT NULL AND password_hash IS NOT NULL AND activated_at >= invited_at)
  );

-- Para listar rápido las invitaciones pendientes (pantalla "Equipo").
CREATE INDEX idx_staff_users_pending ON staff_users (invited_at) WHERE password_hash IS NULL;

-- ---------------------------------------------------------------------------
-- Tokens: nuevo propósito 'invitation', con su propio tope de vida (72 h)
-- ---------------------------------------------------------------------------
ALTER TABLE staff_tokens DROP CONSTRAINT staff_tokens_purpose_check;
ALTER TABLE staff_tokens
  ADD CONSTRAINT chk_staff_tokens_purpose CHECK (
    purpose IN ('password_reset', 'email_change', 'mfa_challenge', 'mfa_enrollment', 'invitation')
  );

ALTER TABLE staff_tokens DROP CONSTRAINT chk_staff_tokens_lifetime;
ALTER TABLE staff_tokens
  ADD CONSTRAINT chk_staff_tokens_lifetime CHECK (
    expires_at > created_at
    AND expires_at <= created_at + CASE WHEN purpose = 'invitation' THEN interval '72 hours' ELSE interval '30 minutes' END
  );

-- Invitación ⇔ cuenta pendiente. Así ni un error del backend puede mandar un
-- enlace de recuperación a una cuenta sin completar, ni una "invitación" que
-- cambie la contraseña de una cuenta que ya está en uso.
CREATE FUNCTION check_staff_token_account() RETURNS trigger AS $$
DECLARE
  pending BOOLEAN;
BEGIN
  SELECT password_hash IS NULL INTO pending FROM staff_users WHERE id = NEW.staff_user_id;
  IF NEW.purpose = 'invitation' AND pending IS NOT TRUE THEN
    RAISE EXCEPTION 'Solo una cuenta pendiente puede tener un token de invitación'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.purpose <> 'invitation' AND pending IS TRUE THEN
    RAISE EXCEPTION 'Una cuenta pendiente solo puede tener tokens de invitación'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_staff_tokens_account
  BEFORE INSERT ON staff_tokens
  FOR EACH ROW EXECUTE FUNCTION check_staff_token_account();
