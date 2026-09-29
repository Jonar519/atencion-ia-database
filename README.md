# atencion-ia-database

Esquema, migraciones, pruebas y datos de prueba de la base de datos de **Atención al
cliente omnicanal con IA** (chat de texto + llamada de voz WebRTC, con escalamiento a un
agente humano). Este repositorio es la **única fuente de verdad** sobre la estructura de
la base de datos: cualquier cambio de esquema se hace aquí, con una migración SQL nueva
y numerada, nunca directamente sobre la base ni desde el backend.

## Relación con los otros repositorios

| Repositorio | Cómo depende de este |
|---|---|
| `atencion-ia-backend` | Lee el esquema con `npx prisma db pull` (Prisma solo como cliente, no gestiona migraciones). Sus tests de integración aplican las migraciones de `../atencion-ia-database/migrations`, así que **las tres carpetas deben ser hermanas**. Usa el Redis de este `docker-compose.yml`. |
| `atencion-ia-frontend` | No depende directamente: habla solo con el backend. |

Este repo no depende de ninguno de los otros dos.

## Contenido del repositorio

```
atencion-ia-database/
├── migrations/                  # SQL numerado, se aplica en orden
│   ├── 001_extensions.sql       # pgcrypto, pgvector
│   ├── 002_enums.sql            # Todos los tipos enumerados, documentados
│   ├── 003_functions.sql        # set_updated_at() para los triggers
│   ├── 004_staff_users.sql      # Agentes y administradores
│   ├── 005_auth.sql             # Refresh tokens rotativos (solo hash) y bloqueo progresivo de login
│   ├── 006_customers.sql        # Clientes finales (sin contraseña) y sesiones del widget
│   ├── 007_knowledge_base.sql   # Artículos y fragmentos con embedding (vector(1024), índice HNSW)
│   ├── 008_conversations.sql    # Conversaciones: estado, agente asignado, prioridad
│   ├── 009_calls.sql            # Llamadas (consentimiento, duración calculada, retención) y participantes
│   ├── 010_messages.sql         # Mensajes (texto y voz), citas del RAG, transcripción de llamadas
│   ├── 011_escalations.sql      # Escalamientos: un solo abierto por conversación
│   ├── 012_audit_and_usage.sql  # Log de auditoría y consumo de proveedores de IA/voz
│   └── 013_kb_chunks_provenance.sql # Trigger: en el índice del RAG solo entra texto literal de artículos
├── seed/
│   └── 001_seed.sql             # Datos de prueba: "Banco Cordillera" (ficticio)
├── tests/
│   ├── 001_constraints.sql      # 38 pruebas de las reglas del esquema (terminan en ROLLBACK)
│   └── 002_rag_provenance.sql   # 6 pruebas del aislamiento del RAG (trigger de la 013)
├── scripts/
│   ├── migrate.bat / migrate.sh # Aplica las migraciones pendientes (cmd.exe · bash/CI)
│   ├── seed.bat / seed.sh       # Carga los datos de prueba
│   └── test.bat / test.sh       # Ejecuta las pruebas del esquema
├── docs/
│   └── domain-model.md          # Modelo de dominio, diagrama ER, reglas e índices
└── docker-compose.yml           # Postgres 16 + pgvector y Redis 7
```

## Servicios y puertos

| Servicio | Contenedor | Puerto del host | Credenciales / notas |
|---|---|---|---|
| PostgreSQL 16 + pgvector 0.8 | `atencion_ia_postgres` | **5434** (→ 5432) | `postgres` / `postgres`, base `atencion_ia` |
| Redis 7 | `atencion_ia_redis` | **6380** (→ 6379) | Sin contraseña (solo desarrollo). `noeviction` + AOF |

Los puertos se eligieron para convivir con el Proyecto 1 (`renta-ia` usa 5433 y 6379) y
con un Postgres instalado localmente en el 5432.

Redis se usa para: colas BullMQ (por eso `maxmemory-policy noeviction`: si Redis
expulsara claves se perderían trabajos), rate limiting, presencia de agentes y pub/sub
de la señalización WebRTC (Fase 5).

## Cómo levantar la base de datos en local

### Windows (cmd.exe): no necesita `psql` instalado

Los `.bat` ejecutan `psql` **dentro del contenedor** (`docker exec`). Solo necesitas
Docker Desktop corriendo.

```bat
:: 1. Levantar Postgres + pgvector y Redis
docker compose up -d

:: 2. Esperar a que ambos digan "(healthy)"
docker compose ps

:: 3. Aplicar las migraciones pendientes
scripts\migrate.bat

:: 4. (Opcional) cargar datos de prueba
scripts\seed.bat

:: 5. (Opcional) ejecutar las pruebas del esquema
scripts\test.bat
```

Salida esperada del paso 3 la primera vez: `Listo: 13 migracion(es) nueva(s)
aplicada(s).` Las siguientes veces: `Listo: 0 ...` (las ya aplicadas se saltan).

Para trabajar sobre otra base (por ejemplo, la de los tests del backend o la de E2E),
créala una vez y define `DB_NAME` antes de los scripts:

```bat
docker exec atencion_ia_postgres psql -U postgres -c "CREATE DATABASE atencion_ia_test"
set DB_NAME=atencion_ia_test
scripts\migrate.bat
```

Para explorar la base a mano:

```bat
docker exec -it atencion_ia_postgres psql -U postgres -d atencion_ia
```

Comandos útiles dentro de `psql`: `\dt` (tablas), `\d+ conversations` (columnas,
índices, CHECKs y FKs de una tabla), `\dT+` (enums), `\q` (salir).

### Linux / macOS / CI: requiere `psql` en el host

```bash
docker compose up -d
export DATABASE_URL="postgresql://postgres:postgres@localhost:5434/atencion_ia"
./scripts/migrate.sh
./scripts/seed.sh
./scripts/test.sh
```

### Empezar de cero

```bat
:: Borra los contenedores Y sus volúmenes (se pierden todos los datos)
docker compose down -v
docker compose up -d
scripts\migrate.bat
scripts\seed.bat
```

## Historial de migraciones (`schema_migrations`)

Existe **desde la primera ejecución**: los scripts registran cada migración aplicada
(`filename`, `applied_at`) y **saltan las que ya corrieron**, así que `migrate` se puede
ejecutar cuantas veces se quiera. Cada migración y su registro corren en **una sola
transacción**: si una falla, no queda aplicada a medias ni marcada como aplicada.

```sql
SELECT filename, applied_at FROM schema_migrations ORDER BY filename;
```

## Convención de migraciones

- Archivos `0NN_descripcion.sql`, en orden. Una migración **nunca se modifica** después
  de haberse aplicado en un entorno compartido: un cambio de esquema siempre es una
  migración nueva.
- Cada archivo empieza con un comentario que explica **por qué** existe cada tabla,
  restricción o índice no obvio.
- No usar `CREATE INDEX CONCURRENTLY`: los scripts ejecutan cada archivo dentro de una
  transacción, y `CONCURRENTLY` no puede correr dentro de una.
- Añadir un valor a un enum: `ALTER TYPE … ADD VALUE` en una migración nueva (el valor
  nuevo no se puede usar en la misma transacción).
- El backend refleja este esquema con `npx prisma db pull`: cualquier cambio aquí
  implica volver a hacer el `pull` allá.

## Modelo de datos

El diseño completo (diagrama ER, máquina de estados, reglas y consultas previstas) está
en [`docs/domain-model.md`](docs/domain-model.md). Resumen:

| Tabla | Descripción |
|---|---|
| `staff_users` | Agentes y administradores (los únicos con contraseña) |
| `refresh_tokens` | Sesiones del staff: hash del refresh token, familia de rotación, revocación |
| `login_attempts` | Fallos de login por cuenta (clave = SHA-256 del correo) para el bloqueo progresivo |
| `customers` | Clientes finales; todos los datos de contacto son opcionales |
| `widget_sessions` | Cómo se identifica un cliente sin contraseña (hash del token del widget) |
| `kb_articles` | Base de conocimiento; solo los `published` alimentan el RAG |
| `kb_chunks` | Fragmentos de artículos con su embedding (`vector(1024)`, HNSW coseno) |
| `conversations` | Hilo de atención: `ai_active` → `waiting_agent` → `agent_active` → `closed` |
| `messages` | Turnos de texto **y de voz** (`channel`), con intención y sentimiento por turno |
| `message_citations` | Qué artículos/fragmentos usó la IA en cada respuesta |
| `calls` | Llamadas de voz: consentimiento, tiempos, duración calculada, retención |
| `call_participants` | Quién estuvo en la llamada (cliente, IA, agentes que se unieron) |
| `call_transcript_segments` | Transcripción final, en orden; cada segmento enlaza a su turno |
| `escalations` | Paso de IA a humano, con la señal que lo disparó |
| `audit_log` | Quién hizo qué, sobre qué y cuándo (sin datos sensibles) |
| `ai_usage` | Consumo de proveedores de IA/voz, para topes de gasto y reporte de costos |
| `schema_migrations` | Historial de migraciones aplicadas (lo gestionan los scripts) |

### Reglas que garantiza la propia base

No dependen de que el backend "se acuerde": están en CHECKs, UNIQUEs parciales y FKs, y
las verifica `tests/001_constraints.sql`.

- Un solo escalamiento abierto por conversación (el backend usa `ON CONFLICT DO NOTHING`).
- Un mensaje reenviado tras reconectar el WebSocket no se duplica (`client_msg_id`).
- Un turno de voz siempre tiene llamada, y esa llamada es de la misma conversación.
- No existe una llamada sin consentimiento, ni dos llamadas activas en la misma conversación.
- La duración de la llamada se calcula, no se escribe.
- No se duplican los embeddings de un mismo fragmento de un artículo.
- **Aislamiento del RAG**: en `kb_chunks` solo puede entrar texto LITERAL del cuerpo vigente de
  su artículo, con su hash correcto (trigger de la migración 013). Ni un bug del backend puede
  meter el mensaje de un cliente en el índice con el que la IA responde a otros clientes.
- Tokens (refresh y widget) guardados solo como hash; correos en minúsculas y únicos.
- Borrar un cliente (derecho de supresión) borra en cascada sus conversaciones,
  mensajes, llamadas y escalamientos; los agentes no se borran, se desactivan.

## Datos de prueba (seed)

`seed/001_seed.sql` crea los datos de un banco ficticio, **Banco Cordillera**. Es
idempotente (IDs fijos + `ON CONFLICT`): se puede ejecutar varias veces sin duplicar.
**No debe ejecutarse en producción.**

**Staff** (contraseña de todos: `Password123!`):

| Nombre | Correo | Rol | Estado |
|---|---|---|---|
| Admin Soporte | `admin@cordillera.example` | admin | disponible |
| Laura Méndez | `laura@cordillera.example` | agent | disponible |
| Diego Rojas | `diego@cordillera.example` | agent | ocupado |
| Sofía Pardo | `sofia@cordillera.example` | agent | **desactivada** (no puede entrar) |

**Sesión de widget de prueba** (cliente anónimo `b0000000-…-0003`): token `wgt_seed-anonimo-cordillera`.
Volver a correr el seed la renueva por 30 días. La usa la demo del backend (`docs/demo-fase3.md`).

**Base de conocimiento:** 11 artículos (bloqueo de tarjeta, cargo no reconocido,
horarios, clave de la app, límites de transferencia, extractos, cajero que no entregó el
dinero, PQR, compras internacionales): 9 publicados, 1 borrador y 1 archivado (estos dos
**no** deben aparecer nunca en el RAG). Se siembran **sin embeddings**: después del seed, en el
backend se corre `npm run kb:reindex` una vez (indexa los 9 publicados; borrador y archivado
quedan fuera).

**Conversaciones** (una por cada estado relevante):

| Asunto | Estado | Canal | Agente | Escalamiento |
|---|---|---|---|---|
| Horario de oficinas | `ai_active` | texto | — | — |
| Cargo no reconocido | `waiting_agent` (prioridad 90) | texto | — | abierto (regla: posible fraude) |
| Reclamo por retiro en cajero | `agent_active` | texto | Laura | asignado (el cliente pidió un humano) |
| Aumento de límite de transferencias | `agent_active` | texto | Diego | asignado |
| Descargar extracto | `closed` (resuelta por la IA) | texto | — | — |
| Clave de la app bloqueada | `closed` (resuelta por agente) | texto | Diego | resuelto (fallo repetido) |
| Consulta por llamada: compras internacionales | `closed` (resuelta por la IA) | **voz** | — | — |

La conversación de voz incluye su llamada (duración 122 s, proveedores `mock`), los dos
participantes, 4 segmentos de transcripción y los 4 turnos correspondientes en
`messages` con `channel = 'voice'`.

Laura y Diego tienen conversaciones distintas asignadas: sirve para probar en la Fase 2
que un agente no ve las conversaciones de otro.

## Pruebas del esquema

```bat
scripts\test.bat
```

Ejecuta `tests/001_constraints.sql` (38 pruebas) y `tests/002_rag_provenance.sql` (6 pruebas del
aislamiento del RAG). En total 44 pruebas que intentan violar cada regla (y
verifican que la base lo impida con el código de error esperado) o comprueban un
comportamiento (duración calculada, `updated_at`, borrado en cascada). Todo corre en una
transacción que termina en `ROLLBACK`: no deja datos y funciona con o sin seed. Si una
prueba falla, el script termina con código de salida distinto de 0 e indica cuál.

## Producción (más adelante)

El despliegue en AWS (RDS for PostgreSQL con pgvector, ElastiCache para Redis) se hace
al final de la materia. Las migraciones se aplican igual, con `migrate.sh` y un
`DATABASE_URL` apuntando a RDS; antes de la primera, el usuario maestro debe crear las
extensiones `pgcrypto` y `vector`.
