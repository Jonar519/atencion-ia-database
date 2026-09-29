-- seed/001_seed.sql
-- Datos de prueba para desarrollo local. NO ejecutar en producción.
-- Empresa ficticia: "Banco Cordillera".
--
-- Idempotente: IDs fijos + ON CONFLICT DO NOTHING. Volver a ejecutarlo no
-- duplica nada (sí restablece el hash de contraseña del staff de prueba).
-- Las marcas de tiempo son relativas a now() del PRIMER sembrado.
--
-- Contraseña de TODO el staff de prueba: Password123!
-- (hash bcrypt real, costo 10).
--
-- La base de conocimiento se siembra SIN embeddings (kb_chunks vacía): los
-- genera el worker de indexación del backend (Fase 3), igual que con un
-- artículo nuevo. Por eso las citas del seed apuntan al artículo, no al fragmento.
--
-- Mapa de IDs (todos UUID v4 válidos):
--   a…  staff             b…  clientes           c…  conversaciones
--   d…  llamadas          e…  escalamientos      f…  artículos KB
--   1…  mensajes (…0CNN = conversación C, mensaje NN)
--   2…  segmentos de transcripción               3…  participantes de llamada

-- ---------------------------------------------------------------------------
-- Staff
-- ---------------------------------------------------------------------------
INSERT INTO staff_users (id, name, email, password_hash, role, availability, max_concurrent, is_active) VALUES
  ('a0000000-0000-4000-8000-000000000001', 'Admin Soporte', 'admin@cordillera.example',
   '$2a$10$xDx7brDnEU371AL7aF0tse7rBu4X.Or66jKV1hqpKFocp133QkF8u', 'admin', 'available', 5, true),
  ('a0000000-0000-4000-8000-000000000002', 'Laura Méndez', 'laura@cordillera.example',
   '$2a$10$xDx7brDnEU371AL7aF0tse7rBu4X.Or66jKV1hqpKFocp133QkF8u', 'agent', 'available', 3, true),
  ('a0000000-0000-4000-8000-000000000003', 'Diego Rojas', 'diego@cordillera.example',
   '$2a$10$xDx7brDnEU371AL7aF0tse7rBu4X.Or66jKV1hqpKFocp133QkF8u', 'agent', 'busy', 3, true),
  -- Desactivada: no puede iniciar sesión ni recibir escalamientos.
  ('a0000000-0000-4000-8000-000000000004', 'Sofía Pardo', 'sofia@cordillera.example',
   '$2a$10$xDx7brDnEU371AL7aF0tse7rBu4X.Or66jKV1hqpKFocp133QkF8u', 'agent', 'offline', 3, false)
ON CONFLICT (id) DO UPDATE SET password_hash = EXCLUDED.password_hash;

-- ---------------------------------------------------------------------------
-- Clientes finales
-- ---------------------------------------------------------------------------
INSERT INTO customers (id, display_name, email, phone, external_ref) VALUES
  ('b0000000-0000-4000-8000-000000000001', 'Camila Torres', 'camila.torres@correo.example', '+573001112233', 'CRM-1001'),
  ('b0000000-0000-4000-8000-000000000002', 'Andrés Gómez', 'andres.gomez@correo.example', '+573004445566', 'CRM-1002'),
  -- Anónimo: entró por el widget sin dar datos.
  ('b0000000-0000-4000-8000-000000000003', NULL, NULL, NULL, NULL),
  ('b0000000-0000-4000-8000-000000000004', 'Valentina Ruiz', 'valentina.ruiz@correo.example', '+573007778899', NULL),
  ('b0000000-0000-4000-8000-000000000005', 'Jorge Herrera', NULL, '+573015550000', NULL)
ON CONFLICT (id) DO NOTHING;

-- Sesión de widget del cliente anónimo. Token de prueba en claro:
-- "seed-widget-token-anonimo" (en la base solo queda su SHA-256).
INSERT INTO widget_sessions (id, customer_id, token_hash, expires_at, user_agent) VALUES
  ('b1000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000003',
   encode(digest('seed-widget-token-anonimo', 'sha256'), 'hex'), now() + interval '30 days', 'Mozilla/5.0 (seed)')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Base de conocimiento
-- ---------------------------------------------------------------------------
INSERT INTO kb_articles (id, slug, title, body, category, tags, status, version, created_by, updated_by, published_at) VALUES
  ('f0000000-0000-4000-8000-000000000001', 'bloquear-tarjeta',
   '¿Cómo bloqueo mi tarjeta débito o crédito?',
   E'Si perdiste tu tarjeta o te la robaron, bloquéala de inmediato. En la app Cordillera Móvil entra a Tarjetas, elige la tarjeta y pulsa "Bloquear". El bloqueo es inmediato y definitivo.\n\nTambién puedes bloquearla llamando a la Línea Cordillera 601 555 0000, disponible las 24 horas, todos los días.\n\nDespués del bloqueo puedes pedir una reposición desde la app; la nueva tarjeta llega en 5 a 8 días hábiles a la dirección registrada. La reposición por robo no tiene costo.',
   'tarjetas', ARRAY['tarjeta', 'bloqueo', 'robo', 'perdida'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '60 days'),

  ('f0000000-0000-4000-8000-000000000002', 'cargo-no-reconocido',
   'Tengo un cargo que no reconozco en mi tarjeta',
   E'Si ves una compra que no hiciste, primero bloquea la tarjeta desde la app para evitar nuevos cargos.\n\nLuego repórtala como no reconocida: en la app entra al movimiento y pulsa "No reconozco esta compra", o comunícate con un asesor. Abrimos una investigación y te damos un número de caso.\n\nEl análisis toma hasta 15 días hábiles. Si se confirma el fraude, el valor se reintegra a tu cuenta. Nunca te pediremos tu clave, el código de seguridad de la tarjeta ni códigos que te lleguen por mensaje de texto.',
   'fraude', ARRAY['fraude', 'cargo', 'compra', 'reclamo'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '60 days'),

  ('f0000000-0000-4000-8000-000000000003', 'horarios-oficinas',
   'Horarios de atención de oficinas y canales',
   E'Las oficinas atienden de lunes a viernes de 8:00 a. m. a 4:00 p. m. y los sábados de 9:00 a. m. a 12:00 m. Algunas oficinas en centros comerciales abren los sábados hasta las 5:00 p. m.; consulta la tuya en la sección "Oficinas" de la app.\n\nLa app Cordillera Móvil, la banca en línea y la Línea Cordillera 601 555 0000 funcionan las 24 horas. Los domingos y festivos las oficinas están cerradas.',
   'canales', ARRAY['horario', 'oficinas', 'atencion'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '60 days'),

  ('f0000000-0000-4000-8000-000000000004', 'recuperar-clave-app',
   'Cómo cambiar o recuperar la clave de la app',
   E'Para cambiar tu clave entra a Perfil > Seguridad > Cambiar clave. La clave debe tener 8 dígitos y no puede ser una secuencia ni tu fecha de nacimiento.\n\nSi olvidaste la clave, en la pantalla de ingreso pulsa "Olvidé mi clave" y valida tu identidad con el código que enviamos a tu celular registrado.\n\nDespués de 3 intentos fallidos la app se bloquea por 24 horas. Si necesitas el acceso antes, un asesor puede desbloquearla después de validar tu identidad.',
   'acceso', ARRAY['clave', 'app', 'bloqueo', 'acceso'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '45 days'),

  ('f0000000-0000-4000-8000-000000000005', 'limites-transferencias',
   'Límites de transferencias y cómo aumentarlos',
   E'El límite diario de transferencias a otras cuentas es de 5.000.000 de pesos por la app y de 3.000.000 por la banca en línea. Las transferencias entre tus propias cuentas no tienen límite.\n\nPuedes aumentar el límite hasta 20.000.000 desde la app en Perfil > Límites. El aumento requiere validar tu identidad y queda activo 24 horas después, por seguridad.',
   'transferencias', ARRAY['transferencia', 'limite', 'monto'], 'published', 2,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '30 days'),

  ('f0000000-0000-4000-8000-000000000006', 'descargar-extractos',
   'Cómo descargar extractos y certificados',
   E'Los extractos de los últimos 24 meses se descargan en PDF desde la app, en Productos > selecciona la cuenta > Extractos.\n\nLos certificados bancarios y el certificado tributario anual se generan en la banca en línea, sección Certificados, sin costo. Si necesitas un extracto más antiguo, solicítalo a un asesor; se entrega en 5 días hábiles.',
   'productos', ARRAY['extracto', 'certificado', 'documentos'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '45 days'),

  ('f0000000-0000-4000-8000-000000000007', 'cajero-no-entrego-dinero',
   'El cajero no me entregó el dinero pero sí lo debitó',
   E'Si un cajero de la red Cordillera no te entregó el dinero, el sistema normalmente lo detecta y reversa el débito en un plazo de 2 días hábiles.\n\nSi pasado ese tiempo el dinero no ha regresado, presenta un reclamo indicando la fecha, la hora, el valor y la ubicación del cajero. La investigación toma hasta 8 días hábiles. Si el cajero es de otra red, el plazo puede ser de hasta 15 días hábiles.',
   'reclamos', ARRAY['cajero', 'retiro', 'reclamo', 'debito'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '40 days'),

  ('f0000000-0000-4000-8000-000000000008', 'presentar-reclamo',
   'Cómo presentar un reclamo o queja formal (PQR)',
   E'Puedes presentar una petición, queja o reclamo desde la app (Ayuda > PQR), en cualquier oficina o con un asesor. Recibirás un número de radicado.\n\nRespondemos en un máximo de 15 días hábiles. Si no estás de acuerdo con la respuesta, puedes acudir al Defensor del Consumidor Financiero del banco, sin costo.',
   'reclamos', ARRAY['pqr', 'queja', 'reclamo'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '40 days'),

  ('f0000000-0000-4000-8000-000000000009', 'compras-internacionales',
   'Compras por internet e internacionales',
   E'Las tarjetas de crédito Cordillera funcionan para compras por internet e internacionales. Por seguridad, las compras en el exterior se deben activar antes de viajar: en la app entra a Tarjetas > Viajes e indica las fechas y los países.\n\nLas compras en otra moneda se liquidan a la tasa del día en que la franquicia procesa la compra y tienen una comisión del 3 %.',
   'tarjetas', ARRAY['internet', 'internacional', 'viaje', 'compra'], 'published', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '20 days'),

  -- Borrador: NO debe aparecer en el RAG.
  ('f0000000-0000-4000-8000-000000000010', 'tarjeta-virtual',
   'Tarjeta virtual para compras en línea (borrador)',
   E'Próximamente podrás generar una tarjeta virtual desde la app, con un código de seguridad dinámico que cambia cada hora.',
   'tarjetas', ARRAY['tarjeta', 'virtual'], 'draft', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', NULL),

  -- Archivado: promoción vencida, tampoco debe aparecer en el RAG.
  ('f0000000-0000-4000-8000-000000000011', 'promocion-cashback-2025',
   'Promoción de cashback 2025 (vencida)',
   E'Durante 2025 las compras en supermercados con la tarjeta de crédito Cordillera recibían un 5 % de devolución. La promoción terminó el 31 de diciembre de 2025.',
   'promociones', ARRAY['promocion', 'cashback'], 'archived', 1,
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', now() - interval '300 days')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Conversaciones (una por cada estado relevante)
--   c1 ai_active      Camila   texto  consulta de horario (la IA la atiende)
--   c2 waiting_agent  Andrés   texto  posible fraude, escalada, en cola
--   c3 agent_active   Valentina texto reclamo, tomada por Laura
--   c4 closed         Camila   texto  resuelta por la IA
--   c5 closed         Jorge    texto  clave bloqueada, resuelta por Diego
--   c6 closed         anónimo  VOZ    consulta por llamada, resuelta por la IA
--   c7 agent_active   Camila   texto  aumento de límite, tomada por Diego
-- ---------------------------------------------------------------------------
INSERT INTO conversations (id, customer_id, assigned_agent_id, status, origin_channel, subject, priority,
                           last_message_at, closed_at, close_reason, created_at) VALUES
  ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', NULL,
   'ai_active', 'text', 'Horario de oficinas', 0,
   now() - interval '14 minutes', NULL, NULL, now() - interval '15 minutes'),
  ('c0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000002', NULL,
   'waiting_agent', 'text', 'Cargo no reconocido', 90,
   now() - interval '7 minutes', NULL, NULL, now() - interval '8 minutes'),
  ('c0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000002',
   'agent_active', 'text', 'Reclamo por retiro en cajero', 60,
   now() - interval '30 minutes', NULL, NULL, now() - interval '40 minutes'),
  ('c0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001', NULL,
   'closed', 'text', 'Descargar extracto', 0,
   now() - interval '2 days' + interval '3 minutes', now() - interval '2 days' + interval '5 minutes', 'resolved_by_ai',
   now() - interval '2 days'),
  ('c0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000003',
   'closed', 'text', 'Clave de la app bloqueada', 40,
   now() - interval '1 day' + interval '20 minutes', now() - interval '1 day' + interval '22 minutes', 'resolved_by_agent',
   now() - interval '1 day'),
  ('c0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000003', NULL,
   'closed', 'voice', 'Consulta por llamada: compras internacionales', 0,
   now() - interval '3 hours' + interval '100 seconds', now() - interval '3 hours' + interval '125 seconds', 'resolved_by_ai',
   now() - interval '3 hours'),
  ('c0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003',
   'agent_active', 'text', 'Aumento de límite de transferencias', 30,
   now() - interval '50 minutes', NULL, NULL, now() - interval '1 hour')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Llamada de voz de c6 (ya terminada) y sus participantes
-- ---------------------------------------------------------------------------
INSERT INTO calls (id, conversation_id, status, consent_given_at, consent_version,
                   started_at, answered_at, ended_at, handled_by_agent_id, end_reason,
                   stt_provider, tts_provider, retain_until, created_at) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000006', 'ended',
   now() - interval '3 hours', 'v1',
   now() - interval '3 hours' + interval '2 seconds',
   now() - interval '3 hours' + interval '3 seconds',
   now() - interval '3 hours' + interval '125 seconds',
   NULL, 'customer_hangup', 'mock', 'mock',
   now() - interval '3 hours' + interval '30 days',
   now() - interval '3 hours' + interval '2 seconds')
ON CONFLICT (id) DO NOTHING;

INSERT INTO call_participants (id, call_id, participant_type, agent_id, joined_at, left_at) VALUES
  ('30000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'customer', NULL,
   now() - interval '3 hours' + interval '2 seconds', now() - interval '3 hours' + interval '125 seconds'),
  ('30000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 'ai', NULL,
   now() - interval '3 hours' + interval '3 seconds', now() - interval '3 hours' + interval '125 seconds')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Mensajes
-- ---------------------------------------------------------------------------
INSERT INTO messages (id, conversation_id, sender_type, sender_agent_id, channel, call_id, content,
                      intent, sentiment, analysis_confidence, client_msg_id, ai_model, ai_latency_ms, created_at) VALUES
  -- c1: consulta simple, la IA responde con la KB.
  ('10000000-0000-4000-8000-000000000101', 'c0000000-0000-4000-8000-000000000001', 'customer', NULL, 'text', NULL,
   'Hola, ¿a qué hora abren las oficinas el sábado?',
   'general_inquiry', 'neutral', 0.93, '40000000-0000-4000-8000-000000000101', NULL, NULL, now() - interval '15 minutes'),
  ('10000000-0000-4000-8000-000000000102', 'c0000000-0000-4000-8000-000000000001', 'ai', NULL, 'text', NULL,
   'Los sábados las oficinas atienden de 9:00 a. m. a 12:00 m. Algunas oficinas en centros comerciales abren hasta las 5:00 p. m.; puedes consultar la tuya en la sección "Oficinas" de la app.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 412, now() - interval '14 minutes'),

  -- c2: posible fraude, cliente molesto → escalada por regla.
  ('10000000-0000-4000-8000-000000000201', 'c0000000-0000-4000-8000-000000000002', 'customer', NULL, 'text', NULL,
   'Me aparece un cobro de 1.250.000 en mi tarjeta que yo NO hice. ¡Necesito que lo solucionen ya!',
   'possible_fraud', 'angry', 0.95, '40000000-0000-4000-8000-000000000201', NULL, NULL, now() - interval '8 minutes'),
  ('10000000-0000-4000-8000-000000000202', 'c0000000-0000-4000-8000-000000000002', 'ai', NULL, 'text', NULL,
   'Entiendo tu preocupación. Por seguridad, bloquea la tarjeta ahora mismo desde la app (Tarjetas > Bloquear). Ya te estoy comunicando con un asesor para abrir la investigación del cargo.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 530, now() - interval '8 minutes' + interval '20 seconds'),
  ('10000000-0000-4000-8000-000000000203', 'c0000000-0000-4000-8000-000000000002', 'system', NULL, 'text', NULL,
   'Tu conversación fue transferida a un asesor. Tiempo estimado de espera: menos de 5 minutos.',
   NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '7 minutes'),

  -- c3: reclamo, el cliente pide un humano, Laura lo toma.
  ('10000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000003', 'customer', NULL, 'text', NULL,
   'Fui a un cajero de ustedes y no me entregó el dinero, pero sí me lo descontaron. Eran 400.000 pesos.',
   'complaint', 'negative', 0.88, '40000000-0000-4000-8000-000000000301', NULL, NULL, now() - interval '40 minutes'),
  ('10000000-0000-4000-8000-000000000302', 'c0000000-0000-4000-8000-000000000003', 'ai', NULL, 'text', NULL,
   'Lamento lo ocurrido. Normalmente el sistema reversa el débito en 2 días hábiles. Si ya pasó ese plazo, puedo ayudarte a presentar el reclamo: necesito la fecha, la hora y la ubicación del cajero.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 488, now() - interval '40 minutes' + interval '15 seconds'),
  ('10000000-0000-4000-8000-000000000303', 'c0000000-0000-4000-8000-000000000003', 'customer', NULL, 'text', NULL,
   'Ya pasaron 5 días y nada. Quiero hablar con una persona, por favor.',
   'human_request', 'angry', 0.91, '40000000-0000-4000-8000-000000000303', NULL, NULL, now() - interval '38 minutes'),
  ('10000000-0000-4000-8000-000000000304', 'c0000000-0000-4000-8000-000000000003', 'system', NULL, 'text', NULL,
   'Un asesor tomará tu caso en breve.',
   NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '38 minutes' + interval '5 seconds'),
  ('10000000-0000-4000-8000-000000000305', 'c0000000-0000-4000-8000-000000000003', 'agent', 'a0000000-0000-4000-8000-000000000002', 'text', NULL,
   'Hola Valentina, soy Laura. Ya revisé tu caso: registré el reclamo con el número R-2026-08812 y lo marqué como prioritario. Te escribo apenas tenga la respuesta del área de cajeros.',
   NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '30 minutes'),

  -- c4: resuelta por la IA.
  ('10000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000004', 'customer', NULL, 'text', NULL,
   '¿Cómo descargo el extracto de mi cuenta de ahorros?',
   'general_inquiry', 'neutral', 0.96, '40000000-0000-4000-8000-000000000401', NULL, NULL, now() - interval '2 days'),
  ('10000000-0000-4000-8000-000000000402', 'c0000000-0000-4000-8000-000000000004', 'ai', NULL, 'text', NULL,
   'Desde la app entra a Productos, elige tu cuenta de ahorros y luego Extractos. Ahí están los últimos 24 meses en PDF.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 390, now() - interval '2 days' + interval '10 seconds'),
  ('10000000-0000-4000-8000-000000000403', 'c0000000-0000-4000-8000-000000000004', 'customer', NULL, 'text', NULL,
   'Listo, ya lo descargué. ¡Gracias!',
   'other', 'positive', 0.97, '40000000-0000-4000-8000-000000000403', NULL, NULL, now() - interval '2 days' + interval '3 minutes'),

  -- c5: la IA no logra resolver (fallo repetido) → Diego lo resuelve.
  ('10000000-0000-4000-8000-000000000501', 'c0000000-0000-4000-8000-000000000005', 'customer', NULL, 'text', NULL,
   'No puedo entrar a la app, dice que mi clave está bloqueada.',
   'account_access', 'negative', 0.84, '40000000-0000-4000-8000-000000000501', NULL, NULL, now() - interval '1 day'),
  ('10000000-0000-4000-8000-000000000502', 'c0000000-0000-4000-8000-000000000005', 'ai', NULL, 'text', NULL,
   'Después de 3 intentos fallidos la app se bloquea por 24 horas. Puedes recuperarla con "Olvidé mi clave" validando el código que llega a tu celular registrado.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 455, now() - interval '1 day' + interval '12 seconds'),
  ('10000000-0000-4000-8000-000000000503', 'c0000000-0000-4000-8000-000000000005', 'customer', NULL, 'text', NULL,
   'Ya lo intenté y el código no me llega, cambié de número.',
   'account_access', 'negative', 0.86, '40000000-0000-4000-8000-000000000503', NULL, NULL, now() - interval '1 day' + interval '2 minutes'),
  ('10000000-0000-4000-8000-000000000504', 'c0000000-0000-4000-8000-000000000005', 'agent', 'a0000000-0000-4000-8000-000000000003', 'text', NULL,
   'Hola Jorge, soy Diego. Validé tu identidad con las preguntas de seguridad, actualicé tu celular y desbloqueé la app. Intenta ingresar de nuevo.',
   NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '1 day' + interval '15 minutes'),
  ('10000000-0000-4000-8000-000000000505', 'c0000000-0000-4000-8000-000000000005', 'customer', NULL, 'text', NULL,
   'Funcionó, muchas gracias Diego.',
   'other', 'positive', 0.95, '40000000-0000-4000-8000-000000000505', NULL, NULL, now() - interval '1 day' + interval '20 minutes'),

  -- c6: llamada de voz. Cada segmento final transcrito es un turno (channel = 'voice').
  ('10000000-0000-4000-8000-000000000601', 'c0000000-0000-4000-8000-000000000006', 'customer', NULL, 'voice', 'd0000000-0000-4000-8000-000000000001',
   'Hola, me voy de viaje a Chile la próxima semana, ¿tengo que hacer algo con mi tarjeta de crédito?',
   'general_inquiry', 'neutral', 0.9, NULL, NULL, NULL, now() - interval '3 hours' + interval '9 seconds'),
  ('10000000-0000-4000-8000-000000000602', 'c0000000-0000-4000-8000-000000000006', 'ai', NULL, 'voice', 'd0000000-0000-4000-8000-000000000001',
   'Sí. Antes de viajar activa las compras en el exterior en la app, en Tarjetas, Viajes, indicando las fechas y el país. Las compras en otra moneda tienen una comisión del tres por ciento.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 610, now() - interval '3 hours' + interval '20 seconds'),
  ('10000000-0000-4000-8000-000000000603', 'c0000000-0000-4000-8000-000000000006', 'customer', NULL, 'voice', 'd0000000-0000-4000-8000-000000000001',
   'Perfecto, y si la pierdo allá, ¿qué hago?',
   'general_inquiry', 'neutral', 0.87, NULL, NULL, NULL, now() - interval '3 hours' + interval '75 seconds'),
  ('10000000-0000-4000-8000-000000000604', 'c0000000-0000-4000-8000-000000000006', 'ai', NULL, 'voice', 'd0000000-0000-4000-8000-000000000001',
   'Bloquéala de inmediato desde la app o llamando a la Línea Cordillera, disponible las veinticuatro horas. Luego puedes pedir la reposición.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 575, now() - interval '3 hours' + interval '100 seconds'),

  -- c7: aumento de límite, el cliente pide un humano, Diego lo toma.
  ('10000000-0000-4000-8000-000000000701', 'c0000000-0000-4000-8000-000000000007', 'customer', NULL, 'text', NULL,
   '¿Cuánto es lo máximo que puedo transferir en un día?',
   'general_inquiry', 'neutral', 0.94, '40000000-0000-4000-8000-000000000701', NULL, NULL, now() - interval '1 hour'),
  ('10000000-0000-4000-8000-000000000702', 'c0000000-0000-4000-8000-000000000007', 'ai', NULL, 'text', NULL,
   'Por la app puedes transferir hasta 5.000.000 de pesos al día a otras cuentas. Puedes subir el límite hasta 20.000.000 en Perfil > Límites; queda activo 24 horas después.',
   NULL, NULL, NULL, NULL, 'mock-chat-v1', 402, now() - interval '1 hour' + interval '8 seconds'),
  ('10000000-0000-4000-8000-000000000703', 'c0000000-0000-4000-8000-000000000007', 'customer', NULL, 'text', NULL,
   'Necesito pagar el arriendo hoy mismo y no puedo esperar 24 horas, ¿me comunicas con un asesor?',
   'human_request', 'negative', 0.89, '40000000-0000-4000-8000-000000000703', NULL, NULL, now() - interval '55 minutes'),
  ('10000000-0000-4000-8000-000000000704', 'c0000000-0000-4000-8000-000000000007', 'agent', 'a0000000-0000-4000-8000-000000000003', 'text', NULL,
   'Hola Camila, soy Diego. Por seguridad el aumento no se puede activar de inmediato, pero puedes hacer dos transferencias hoy y mañana, o pagar en una oficina. ¿Te ayudo con alguna de esas opciones?',
   NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '50 minutes')
ON CONFLICT (id) DO NOTHING;

-- Citas del RAG (a nivel de artículo: los fragmentos todavía no existen, ver encabezado).
INSERT INTO message_citations (message_id, rank, article_id, chunk_id, article_version, score) VALUES
  ('10000000-0000-4000-8000-000000000102', 1, 'f0000000-0000-4000-8000-000000000003', NULL, 1, 0.86),
  ('10000000-0000-4000-8000-000000000202', 1, 'f0000000-0000-4000-8000-000000000002', NULL, 1, 0.91),
  ('10000000-0000-4000-8000-000000000202', 2, 'f0000000-0000-4000-8000-000000000001', NULL, 1, 0.78),
  ('10000000-0000-4000-8000-000000000302', 1, 'f0000000-0000-4000-8000-000000000007', NULL, 1, 0.89),
  ('10000000-0000-4000-8000-000000000402', 1, 'f0000000-0000-4000-8000-000000000006', NULL, 1, 0.9),
  ('10000000-0000-4000-8000-000000000502', 1, 'f0000000-0000-4000-8000-000000000004', NULL, 1, 0.88),
  ('10000000-0000-4000-8000-000000000602', 1, 'f0000000-0000-4000-8000-000000000009', NULL, 1, 0.87),
  ('10000000-0000-4000-8000-000000000604', 1, 'f0000000-0000-4000-8000-000000000001', NULL, 1, 0.81),
  ('10000000-0000-4000-8000-000000000702', 1, 'f0000000-0000-4000-8000-000000000005', NULL, 2, 0.9)
ON CONFLICT (message_id, rank) DO NOTHING;

-- Transcripción de la llamada de c6: un segmento final por turno.
INSERT INTO call_transcript_segments (id, call_id, seq, speaker, text, start_ms, end_ms, confidence, message_id) VALUES
  ('20000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 0, 'customer',
   'Hola, me voy de viaje a Chile la próxima semana, ¿tengo que hacer algo con mi tarjeta de crédito?',
   1200, 6100, 0.94, '10000000-0000-4000-8000-000000000601'),
  ('20000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 1, 'ai',
   'Sí. Antes de viajar activa las compras en el exterior en la app, en Tarjetas, Viajes, indicando las fechas y el país. Las compras en otra moneda tienen una comisión del tres por ciento.',
   7000, 17500, NULL, '10000000-0000-4000-8000-000000000602'),
  ('20000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 2, 'customer',
   'Perfecto, y si la pierdo allá, ¿qué hago?',
   69000, 72000, 0.91, '10000000-0000-4000-8000-000000000603'),
  ('20000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001', 3, 'ai',
   'Bloquéala de inmediato desde la app o llamando a la Línea Cordillera, disponible las veinticuatro horas. Luego puedes pedir la reposición.',
   73000, 97000, NULL, '10000000-0000-4000-8000-000000000604')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Escalamientos
-- ---------------------------------------------------------------------------
INSERT INTO escalations (id, conversation_id, call_id, triggering_message_id, trigger_source, reason, signal, priority,
                         status, assigned_agent_id, assigned_at, resolved_at, resolution_note, created_at) VALUES
  -- c2: abierto, en cola (nadie lo ha tomado).
  ('e0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000002', NULL,
   '10000000-0000-4000-8000-000000000201', 'rule', 'possible_fraud',
   '{"rule": "fraud_keywords", "matched": ["cobro", "yo no hice"], "intent": "possible_fraud", "sentiment": "angry", "confidence": 0.95}',
   90, 'open', NULL, NULL, NULL, NULL, now() - interval '7 minutes'),
  -- c3: asignado a Laura.
  ('e0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', NULL,
   '10000000-0000-4000-8000-000000000303', 'customer_request', 'human_requested',
   '{"intent": "human_request", "sentiment": "angry", "confidence": 0.91, "turns_without_resolution": 2}',
   60, 'assigned', 'a0000000-0000-4000-8000-000000000002', now() - interval '31 minutes', NULL, NULL,
   now() - interval '38 minutes'),
  -- c5: resuelto por Diego (la IA falló dos veces seguidas).
  ('e0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000005', NULL,
   '10000000-0000-4000-8000-000000000503', 'rule', 'repeated_failure',
   '{"rule": "repeated_intent", "intent": "account_access", "repeats": 2}',
   40, 'resolved', 'a0000000-0000-4000-8000-000000000003', now() - interval '1 day' + interval '10 minutes',
   now() - interval '1 day' + interval '22 minutes', 'Identidad validada, celular actualizado y app desbloqueada.',
   now() - interval '1 day' + interval '2 minutes'),
  -- c7: asignado a Diego.
  ('e0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000007', NULL,
   '10000000-0000-4000-8000-000000000703', 'customer_request', 'human_requested',
   '{"intent": "human_request", "sentiment": "negative", "confidence": 0.89}',
   30, 'assigned', 'a0000000-0000-4000-8000-000000000003', now() - interval '52 minutes', NULL, NULL,
   now() - interval '55 minutes')
ON CONFLICT (id) DO NOTHING;
