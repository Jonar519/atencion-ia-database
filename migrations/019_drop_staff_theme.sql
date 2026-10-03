-- 019_drop_staff_theme.sql
-- El tema de la aplicación lo decide SIEMPRE el sistema operativo del
-- dispositivo (prefers-color-scheme), en todas las pantallas y para todos los
-- roles: ya no hay una preferencia de tema guardada ni elegible por el usuario.
-- La columna de la 015 deja de tener sentido y se elimina (su CHECK se va con
-- ella). Si algún día vuelve la opción, se reintroduce con una migración nueva.

ALTER TABLE staff_users DROP COLUMN theme;
