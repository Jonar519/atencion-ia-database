# atencion-ia-database

Esquema, migraciones y datos de prueba de la base de datos de **Atención al cliente
omnicanal con IA** (chat de texto + llamada de voz WebRTC, con escalamiento a un agente
humano). Este repositorio es la **única fuente de verdad** sobre la estructura de la base
de datos: cualquier cambio de esquema se hace aquí, con una migración SQL nueva y
numerada, nunca directamente sobre la base ni desde el backend.

## Relación con los otros repositorios

| Repositorio | Cómo depende de este |
|---|---|
| `atencion-ia-backend` | Lee el esquema con `npx prisma db pull` (Prisma solo como cliente, no gestiona migraciones). Sus tests de integración aplican las migraciones de `../atencion-ia-database/migrations`, así que **las tres carpetas deben ser hermanas**. Usa el Redis de este `docker-compose.yml`. |
| `atencion-ia-frontend` | No depende directamente: habla solo con el backend. |

Este repo no depende de ninguno de los otros dos.

## Estado

**Fase 0**: modelo de dominio diseñado y documentado en
[`docs/domain-model.md`](docs/domain-model.md). Las migraciones, el `docker-compose.yml`
(Postgres 16 + pgvector y Redis), los scripts `migrate`/`seed` (`.bat` para cmd.exe y
`.sh`) y el seed llegan en la Fase 1, con sus instrucciones completas en este README.
