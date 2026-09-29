-- 005_auth.sql
-- Sesión del staff (refresh tokens rotativos) y bloqueo progresivo de login.
-- Mismo diseño que funcionó en el Proyecto 1, desde el día 1.

-- Refresh tokens (cookie httpOnly). Se guarda solo el SHA-256 del token: si
-- alguien lee esta tabla, no puede usar los tokens.
--
-- Rotación: cada uso entrega un token nuevo y revoca el anterior
-- (replaced_by). Todos los tokens de un mismo inicio de sesión comparten
-- family_id. Si llega un token YA rotado (reutilización = probable robo),
-- se revoca la familia entera y el usuario tiene que volver a iniciar sesión.
CREATE TABLE refresh_tokens (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_user_id  UUID NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  family_id      UUID NOT NULL,
  token_hash     CHAR(64) NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at     TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at     TIMESTAMPTZ,
  revoke_reason  VARCHAR(30)
                   CHECK (revoke_reason IN ('rotated', 'logout', 'reuse_detected', 'expired')),
  replaced_by    UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL,
  user_agent     VARCHAR(200),
  CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash),
  CONSTRAINT chk_refresh_tokens_expiry CHECK (expires_at > created_at),
  -- Revocado ⇔ tiene motivo.
  CONSTRAINT chk_refresh_tokens_revoked CHECK ((revoked_at IS NULL) = (revoke_reason IS NULL))
);

CREATE INDEX idx_refresh_tokens_staff_user ON refresh_tokens (staff_user_id);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
CREATE INDEX idx_refresh_tokens_replaced_by ON refresh_tokens (replaced_by) WHERE replaced_by IS NOT NULL;
-- Limpieza periódica de expirados.
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens (expires_at);

-- Intentos fallidos de login, por CUENTA (clave = SHA-256 del correo
-- normalizado). Se guarda igual para correos que no existen: así el bloqueo
-- se comporta idéntico y no revela si una cuenta existe. El límite por IP lo
-- hace el rate limiter (Redis).
CREATE TABLE login_attempts (
  key_hash      CHAR(64) PRIMARY KEY CHECK (key_hash ~ '^[0-9a-f]{64}$'),
  failures      INT NOT NULL DEFAULT 0 CHECK (failures >= 0),
  locked_until  TIMESTAMPTZ,
  last_failure  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Limpieza de registros viejos.
CREATE INDEX idx_login_attempts_last_failure ON login_attempts (last_failure);
