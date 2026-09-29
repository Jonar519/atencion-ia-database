-- 004_staff_users.sql
-- Agentes y administradores: las únicas personas con contraseña.
--
-- email: siempre en minúsculas (el backend normaliza; el CHECK impide que
-- alguien lo salte desde psql), así el UNIQUE no se burla con mayúsculas.
-- is_active: los agentes se desactivan, no se borran (conversaciones,
-- llamadas y escalamientos pasados los referencian con ON DELETE RESTRICT).

CREATE TABLE staff_users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            VARCHAR(150) NOT NULL CHECK (length(btrim(name)) > 0),
  email           VARCHAR(254) NOT NULL
                    CHECK (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  password_hash   VARCHAR(255) NOT NULL,
  role            staff_role NOT NULL DEFAULT 'agent',
  availability    agent_availability NOT NULL DEFAULT 'offline',
  -- Conversaciones simultáneas que acepta. Lo usa el motor de escalamiento.
  max_concurrent  SMALLINT NOT NULL DEFAULT 3 CHECK (max_concurrent BETWEEN 1 AND 20),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_staff_users_email UNIQUE (email)
);

-- Motor de escalamiento: "agentes activos y disponibles".
CREATE INDEX idx_staff_users_available
  ON staff_users (availability)
  WHERE is_active;

CREATE TRIGGER trg_staff_users_updated_at
  BEFORE UPDATE ON staff_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
