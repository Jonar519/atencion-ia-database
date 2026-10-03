-- 015_staff_identity.sql
-- Fase 7, bloque A: identidad del staff.
--   - Perfil (teléfono, tema, avatar), MFA (TOTP) y anonimización de cuentas.
--   - Tokens de UN SOLO USO (recuperar contraseña, cambiar correo, desafío y
--     enrolamiento de MFA): solo se guarda su SHA-256; la base impone que haya
--     a lo sumo UNO vigente por propósito y persona, y que vivan poco.
--   - Códigos de respaldo de MFA (hash, un solo uso).
--   - Bandeja del proveedor de correo SIMULADO (email_outbox).
--   - Sesiones: IP TRUNCADA y ubicación aproximada, para el panel de sesiones.

-- ---------------------------------------------------------------------------
-- Perfil, MFA y anonimización
-- ---------------------------------------------------------------------------
ALTER TABLE staff_users
  ADD COLUMN phone VARCHAR(30)
    CHECK (phone IS NULL OR phone ~ '^\+?[0-9][0-9 ()-]{6,29}$'),
  ADD COLUMN theme VARCHAR(10) NOT NULL DEFAULT 'system'
    CHECK (theme IN ('system', 'light', 'dark')),
  -- Clave del avatar en el almacenamiento (el archivo NO vive en la base).
  ADD COLUMN avatar_storage_key VARCHAR(300),
  -- Secreto TOTP CIFRADO por el backend (AES-256-GCM); nunca en claro.
  ADD COLUMN mfa_secret_encrypted TEXT,
  ADD COLUMN mfa_enabled_at TIMESTAMPTZ,
  -- Último paso de tiempo TOTP aceptado: un código no se puede reutilizar.
  ADD COLUMN mfa_last_used_step BIGINT CHECK (mfa_last_used_step IS NULL OR mfa_last_used_step >= 0),
  -- Cuenta anonimizada ("eliminada"): la fila queda solo como referencia del historial.
  ADD COLUMN deleted_at TIMESTAMPTZ;

-- MFA activo ⇒ hay secreto.
ALTER TABLE staff_users
  ADD CONSTRAINT chk_staff_users_mfa CHECK (mfa_enabled_at IS NULL OR mfa_secret_encrypted IS NOT NULL);

-- Una cuenta anonimizada no conserva NADA personal y no puede entrar.
ALTER TABLE staff_users
  ADD CONSTRAINT chk_staff_users_deleted CHECK (
    deleted_at IS NULL OR (
      NOT is_active
      AND email LIKE '%@anonimizado.invalid'
      AND phone IS NULL
      AND avatar_storage_key IS NULL
      AND mfa_secret_encrypted IS NULL
      AND mfa_enabled_at IS NULL
    )
  );

-- ---------------------------------------------------------------------------
-- Tokens de un solo uso
-- ---------------------------------------------------------------------------
CREATE TABLE staff_tokens (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_user_id  UUID NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  purpose        VARCHAR(20) NOT NULL
                   CHECK (purpose IN ('password_reset', 'email_change', 'mfa_challenge', 'mfa_enrollment')),
  token_hash     CHAR(64) NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  -- Solo para email_change: el correo nuevo, que se confirma con el token.
  new_email      VARCHAR(254)
                   CHECK (new_email IS NULL OR (new_email = lower(new_email) AND new_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  -- Intentos fallidos contra un desafío de MFA (el backend corta en 5).
  attempts       SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  used_at        TIMESTAMPTZ,
  CONSTRAINT uq_staff_tokens_hash UNIQUE (token_hash),
  CONSTRAINT chk_staff_tokens_email_change CHECK ((purpose = 'email_change') = (new_email IS NOT NULL)),
  -- Viven poco: ninguno más de 30 minutos (el backend usa 15 para correo y 5 para MFA).
  CONSTRAINT chk_staff_tokens_lifetime
    CHECK (expires_at > created_at AND expires_at <= created_at + interval '30 minutes'),
  CONSTRAINT chk_staff_tokens_used CHECK (used_at IS NULL OR used_at >= created_at)
);

-- A lo sumo UN token sin usar por propósito y persona: pedir otro enlace
-- invalida el anterior (el backend lo marca usado en la misma transacción).
CREATE UNIQUE INDEX uq_staff_tokens_one_live
  ON staff_tokens (staff_user_id, purpose)
  WHERE used_at IS NULL;

-- Limpieza periódica.
CREATE INDEX idx_staff_tokens_expires ON staff_tokens (expires_at);

-- ---------------------------------------------------------------------------
-- Códigos de respaldo de MFA (hash; un solo uso)
-- ---------------------------------------------------------------------------
CREATE TABLE mfa_backup_codes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_user_id  UUID NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  code_hash      CHAR(64) NOT NULL CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at        TIMESTAMPTZ,
  CONSTRAINT uq_mfa_backup_codes UNIQUE (staff_user_id, code_hash),
  CONSTRAINT chk_mfa_backup_codes_used CHECK (used_at IS NULL OR used_at >= created_at)
);

-- ---------------------------------------------------------------------------
-- Correo SIMULADO (EMAIL_PROVIDER=mock): lo "enviado" queda aquí para leerlo con psql.
-- El proveedor real (SMTP) NO escribe en esta tabla.
-- ---------------------------------------------------------------------------
CREATE TABLE email_outbox (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  to_address        VARCHAR(254) NOT NULL,
  subject           VARCHAR(200) NOT NULL,
  body_text         TEXT NOT NULL CHECK (length(body_text) <= 10000),
  template          VARCHAR(40) NOT NULL,
  related_staff_id  UUID REFERENCES staff_users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_email_outbox_created ON email_outbox (created_at DESC);

-- ---------------------------------------------------------------------------
-- Sesiones: IP truncada y ubicación aproximada
-- ---------------------------------------------------------------------------
ALTER TABLE refresh_tokens
  -- IPv4 con el último octeto en 0 (x.y.z.0) o IPv6 recortada a /48. Nunca la IP completa.
  ADD COLUMN ip_address VARCHAR(45)
    CHECK (ip_address IS NULL OR ip_address ~ '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.0|[0-9a-f:]+::)$'),
  ADD COLUMN location_label VARCHAR(120);

-- Nuevos motivos de revocación.
ALTER TABLE refresh_tokens DROP CONSTRAINT refresh_tokens_revoke_reason_check;
ALTER TABLE refresh_tokens
  ADD CONSTRAINT chk_refresh_tokens_revoke_reason CHECK (
    revoke_reason IN (
      'rotated', 'logout', 'reuse_detected', 'expired',
      'password_reset', 'password_changed', 'revoked_by_user', 'account_deleted'
    )
  );
