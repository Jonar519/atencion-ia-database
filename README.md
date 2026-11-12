# atencion-ia-database: la base de datos de Atención IA

Este repositorio es la **única fuente de verdad** del esquema de PostgreSQL de **Atención IA**: las
migraciones SQL, los datos de prueba (seed) y las pruebas del esquema. Ningún otro repositorio crea
ni modifica tablas. La **guía completa para evaluar el proyecto** (acceso, roles y la prueba de cada
función paso a paso) está en el README principal, en
[atencion-ia-backend](https://github.com/Jonar519/atencion-ia-backend#readme).

## Contenido

1. [Qué es](#1-qué-es)
2. [Cómo funciona](#2-cómo-funciona)
3. [Tecnologías](#3-tecnologías)
4. [Qué se necesita](#4-qué-se-necesita)
5. [Acceso y roles](#5-acceso-y-roles)
6. [Guía de pruebas de la base](#6-guía-de-pruebas-de-la-base)
7. [Pruebas automatizadas](#7-pruebas-automatizadas)
8. [Limitaciones y decisiones de diseño](#8-limitaciones-y-decisiones-de-diseño)
9. [Solución de problemas](#9-solución-de-problemas)
10. [Estructura del repositorio](#10-estructura-del-repositorio)
11. [Glosario](#11-glosario)

## 1. Qué es

La base guarda todo lo que el sistema necesita: el equipo (asesores y administradores) y su
seguridad (sesiones, verificación en dos pasos, invitaciones), los clientes anónimos y sus sesiones
del chat, la base de conocimiento con sus embeddings para la búsqueda por significado, las
conversaciones, los mensajes de texto y de voz, las llamadas con su consentimiento y transcripción,
los escalamientos, los adjuntos, las respuestas predefinidas, la auditoría y el consumo de los
servicios de IA y voz.

Además, **protege las reglas importantes por sí misma** (con restricciones, índices y triggers), de
modo que se cumplen aunque el código del backend tenga un error. Por ejemplo: un solo escalamiento
abierto por conversación, ninguna llamada sin consentimiento y, en el índice que usa la IA, solo
texto literal de los artículos.

## 2. Cómo funciona

- **Migraciones numeradas** (`migrations/001_…sql` a `019_…sql`): cada cambio del esquema es un
  archivo SQL nuevo que se aplica una sola vez, en orden. La tabla `schema_migrations` registra cuáles
  ya se aplicaron, así que correr el script de nuevo no repite nada.
- **El backend no migra:** lee el esquema con Prisma (solo como cliente) y sus tests aplican estas
  mismas migraciones en una base desechable. Por eso los tres repositorios deben estar en carpetas
  hermanas.
- **Seed** (`seed/001_seed.sql`): datos ficticios de "Banco Cordillera" para desarrollo; se puede
  cargar varias veces sin duplicar y **nunca** se carga en producción.
- **Pruebas del esquema** (`tests/*.sql`): intentan romper cada regla dentro de una transacción que
  termina en `ROLLBACK` (no dejan datos).

```mermaid
erDiagram
  STAFF_USERS ||--o{ CONVERSATIONS : "atiende"
  CUSTOMERS ||--o{ WIDGET_SESSIONS : "tiene"
  CUSTOMERS ||--o{ CONVERSATIONS : "abre"
  CONVERSATIONS ||--o{ MESSAGES : "contiene"
  CONVERSATIONS ||--o{ CALLS : "tiene"
  CONVERSATIONS ||--o{ ESCALATIONS : "escala"
  CALLS ||--o{ CALL_TRANSCRIPT_SEGMENTS : "transcribe"
  MESSAGES ||--o| MESSAGE_ATTACHMENTS : "adjunta"
  KB_ARTICLES ||--o{ KB_CHUNKS : "se divide en"
```

El modelo completo, con todas las tablas, el diagrama entidad-relación y los índices, está en
[docs/domain-model.md](docs/domain-model.md). La lista de reglas garantizadas por la base, en la
[referencia técnica](docs/referencia-tecnica.md#reglas-que-garantiza-la-propia-base).

## 3. Tecnologías

| Tecnología                      | Versión                                     | Para qué se usa                                                     | Por qué se eligió                                                                                     |
| ------------------------------- | ------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **PostgreSQL**                  | 16 (imagen `pgvector/pgvector:pg16`)        | Base de datos relacional                                            | CHECK, índices únicos parciales, FKs compuestas, columnas calculadas y triggers para proteger reglas. |
| **pgvector**                    | incluida en la imagen (índice HNSW)          | Embeddings de 1024 dimensiones y búsqueda por similitud             | Datos y vectores en la misma base, con transacciones.                                                 |
| **pgcrypto**                    | extensión de PostgreSQL                     | `gen_random_uuid()` y hashes                                        | Identificadores y hashes generados en la base.                                                        |
| **Redis**                       | 7 (imagen `redis:7-alpine`)                 | Colas, límites de uso y pub/sub del backend (solo en desarrollo aquí) | El mismo `docker-compose.yml` levanta todo lo que el backend necesita.                              |
| **Docker Compose**              | —                                           | Levanta PostgreSQL (puerto 5434) y Redis (6380) en desarrollo       | Mismo entorno en cualquier equipo.                                                                    |
| **SQL puro** + scripts `.bat`/`.sh` | —                                       | Migraciones, seed y pruebas                                         | Sin ORM gestionando el esquema: lo que se revisa es exactamente lo que corre.                        |
| **GitHub Actions** · **gitleaks** | gitleaks en la CI                         | Base limpia, migraciones dos veces, seed dos veces, pruebas y secretos | Cada `push` demuestra que el esquema se crea de cero y que las reglas se cumplen.                   |
| **Railway**                     | —                                           | PostgreSQL con pgvector y Redis en producción                       | Mismo proyecto que la API, con red privada.                                                           |

## 4. Qué se necesita

- **Para evaluar en producción:** nada de este repositorio; solo el navegador (ver
  [Qué necesita el profesor](https://github.com/Jonar519/atencion-ia-backend#4-qué-necesita-el-profesor)).
- **Para levantar la base en local:** Docker Desktop en marcha. En Windows (`cmd.exe`) no hace falta
  `psql`: los scripts `.bat` lo usan dentro del contenedor. En Linux o macOS se necesita el cliente
  `psql`.

```bat
cd atencion-ia-database
docker compose up -d
scripts\migrate.bat
scripts\seed.bat
```

En Linux o macOS:

```bash
cd atencion-ia-database
docker compose up -d
export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"
./scripts/migrate.sh
./scripts/seed.sh
```

Esperado: `docker compose ps` muestra `atencion_ia_postgres` y `atencion_ia_redis` en ejecución; la
migración termina con `Listo: N migracion(es) nueva(s) aplicada(s).` y el seed con
`Datos de prueba cargados correctamente.` Valores de conexión de desarrollo (solo locales):

```ini
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/atencion_ia
REDIS_URL=redis://localhost:6380
```

Después sigue con el backend y el frontend:
[opción local](https://github.com/Jonar519/atencion-ia-backend#b-opción-local-opcional).

## 5. Acceso y roles

Los roles del equipo son dos (`admin` y `agent`, tipo `staff_role`); los clientes no tienen cuenta,
solo sesiones anónimas. Cómo se entra a la aplicación, las invitaciones y la verificación en dos
pasos: [Acceso y roles](https://github.com/Jonar519/atencion-ia-backend#5-acceso-y-roles). Las
cuentas del seed (listadas en la
[referencia técnica](docs/referencia-tecnica.md#datos-de-prueba-seed)) **solo existen en local**: en
producción no se carga el seed.

## 6. Guía de pruebas de la base

Con la base local levantada (sección 4). Las funciones de la aplicación se prueban con la
[guía principal](https://github.com/Jonar519/atencion-ia-backend#6-guía-de-pruebas-función-por-función).

| Función                         | Qué hace                                                 | Pasos para probarla                                                                                                                                                              | Resultado esperado                                                                                         |
| ------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Migraciones repetibles          | Aplica solo lo pendiente                                 | Corre `scripts\migrate.bat` dos veces                                                                                                                                            | La segunda vez lista cada archivo como `ya aplicada` y termina con `Listo: 0 migracion(es) nueva(s) aplicada(s).` |
| Seed idempotente                | Recargar los datos de prueba no los duplica              | Corre `scripts\seed.bat` dos veces y cuenta: `docker exec atencion_ia_postgres psql -U postgres -d atencion_ia -At -c "SELECT count(*) FROM kb_articles"`                         | `11` las dos veces (9 publicados, 1 borrador y 1 archivado).                                               |
| Pruebas del esquema             | Intenta romper cada regla                                | `scripts\test.bat` (o `./scripts/test.sh`)                                                                                                                                       | Recorre los 7 archivos de `tests/` y termina con `Todas las pruebas del esquema pasaron.`                  |
| Regla: duración calculada       | La duración de una llamada no se puede escribir          | `docker exec atencion_ia_postgres psql -U postgres -d atencion_ia -c "BEGIN; UPDATE calls SET duration_seconds = 5; ROLLBACK;"`                                                  | `ERROR: column "duration_seconds" can only be updated to DEFAULT` (es una columna calculada).              |
| Regla: correos en minúsculas    | La base rechaza un correo con mayúsculas                 | `docker exec atencion_ia_postgres psql -U postgres -d atencion_ia -c "BEGIN; INSERT INTO staff_users (name, email, role, password_hash) VALUES ('Prueba','MAYUS@ejemplo.com','agent','x'); ROLLBACK;"` | `ERROR: new row for relation "staff_users" violates check constraint "staff_users_email_check"`.          |
| Modelo de datos                 | Documenta tablas, relaciones e índices                   | Abre [docs/domain-model.md](docs/domain-model.md)                                                                                                                                | Diagrama entidad-relación y cada regla con la migración que la crea.                                       |

## 7. Pruebas automatizadas

| Comando                                       | Qué cubre                                                                                                                                                         | Resultado esperado                         |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `scripts\test.bat` o `./scripts/test.sh`      | **112 pruebas** en 7 archivos: 38 de reglas generales, 6 de aislamiento del RAG, 13 de voz, 18 de identidad del equipo, 10 de respuestas predefinidas, 9 de adjuntos y 18 de invitaciones | `Todas las pruebas del esquema pasaron.`  |
| CI (`.github/workflows/`)                     | Base **limpia**, migraciones dos veces (la segunda no aplica nada), seed dos veces con conteos, pruebas del esquema y gitleaks                                    | En verde en cada `push`.                   |

Además, los tests de integración del backend aplican estas migraciones reales en su propia base.

## 8. Limitaciones y decisiones de diseño

- **El seed es solo para desarrollo:** contiene contraseñas de prueba públicas y nunca se ejecuta en
  producción. Por eso la base de conocimiento de producción empieza vacía.
- **Los artículos del seed vienen sin embeddings:** hay que indexarlos desde el backend
  (`npm run kb:reindex`), porque los vectores dependen del modelo de embeddings configurado.
- **Prisma no gestiona el esquema:** nunca `prisma migrate` ni `prisma db push`; los cambios son
  migraciones SQL nuevas aquí.
- **Las migraciones no corren solas en producción:** se aplican a mano con el mismo script antes de
  desplegar el backend.
- **Redis sin contraseña** en el `docker-compose.yml`: solo para desarrollo local.

## 9. Solución de problemas

| Síntoma                                                  | Qué hacer                                                                                                     |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `docker compose up -d` falla: el puerto 5434 o 6380 está ocupado | Otro servicio usa ese puerto: detenlo o cambia el puerto publicado en `docker-compose.yml` (y en el `.env` del backend). |
| `ERROR: no se pudo conectar a la base atencion_ia en el contenedor…` | Docker Desktop no está en marcha o falta `docker compose up -d`: levántalo y espera a que el contenedor esté `healthy`. |
| `migrate.sh` o `seed.sh`: `psql: command not found`      | Instala el cliente de PostgreSQL, o usa los `.bat` en Windows.                                                 |
| `ERROR: define la variable de entorno DATABASE_URL`      | En Linux o macOS: `export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"`.           |
| `ERROR al aplicar <archivo>.sql`                         | La migración no se registra y se puede corregir y repetir. Las migraciones ya aplicadas no se editan: un cambio nuevo es un archivo nuevo. Para empezar de cero, ver la [referencia técnica](docs/referencia-tecnica.md#empezar-de-cero). |

## 10. Estructura del repositorio

```
atencion-ia-database/
├── migrations/          # 001 … 019: extensiones, tipos, tablas, reglas y triggers, en orden
├── seed/001_seed.sql    # datos ficticios de Banco Cordillera (solo desarrollo)
├── tests/               # 7 archivos de pruebas del esquema (terminan en ROLLBACK)
├── scripts/             # migrate, seed y test, en .bat (Windows) y .sh (Linux, macOS y CI)
├── docs/
│   ├── domain-model.md        # modelo de dominio, diagrama ER, reglas e índices
│   └── referencia-tecnica.md  # detalle de cada archivo, puertos, migraciones, seed y CI
└── docker-compose.yml   # PostgreSQL 16 + pgvector y Redis 7
```

## 11. Glosario

| Término                  | Qué significa aquí                                                                                         |
| ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **Migración**            | Archivo SQL numerado que cambia el esquema; se aplica una vez y queda registrado.                          |
| **Seed**                 | Datos de prueba que se cargan en una base de desarrollo.                                                   |
| **Idempotente**          | Que se puede ejecutar varias veces con el mismo resultado (sin duplicar).                                  |
| **CHECK / índice único parcial** | Reglas de la base: una condición que toda fila debe cumplir / unicidad solo entre filas que cumplen una condición (por ejemplo, escalamientos abiertos). |
| **Trigger**              | Función que la base ejecuta sola al insertar o cambiar filas.                                              |
| **Embedding / pgvector** | Lista de números que representa el significado de un texto / extensión que los guarda y compara.           |
| **HNSW**                 | Tipo de índice de pgvector para encontrar rápido los vectores más parecidos.                               |

El glosario completo del proyecto está en el
[README principal](https://github.com/Jonar519/atencion-ia-backend#11-glosario).
