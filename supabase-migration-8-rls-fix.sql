-- Migration 8: RLS hardening — remove phantom and permissive anon policies
-- Fecha: 2026-06-05
-- Ejecutar en: Supabase Dashboard → SQL Editor

-- ── RIESGO 1: Política fantasma en config_required_docs ──────────────────────
-- Migration 2 creó "allow_all_config_required_docs" con USING (true).
-- Migration 7 intentó borrar "allow_all_member_required_docs" (nombre incorrecto).
-- Esta política puede seguir activa y permitir escritura total sin restricciones.
DROP POLICY IF EXISTS allow_all_config_required_docs ON config_required_docs;

-- ── RIESGO 2: anon puede leer TODOS los códigos de invitación ────────────────
-- Cualquier usuario no autenticado podía hacer SELECT * FROM invite_codes.
-- La validación ahora ocurre 100% server-side via /api/validate-invite.
DROP POLICY IF EXISTS "anon_validate_code" ON invite_codes;

-- ── RIESGO 3: anon podía marcar cualquier código como usado ──────────────────
-- Un bot podía quemar todos los códigos de invitación.
-- El marcado ahora ocurre server-side en /api/notify-applicant con service role.
DROP POLICY IF EXISTS "anon_mark_used" ON invite_codes;

-- Verificación post-ejecución:
-- SELECT tablename, policyname FROM pg_policies
-- WHERE schemaname = 'public'
--   AND policyname IN (
--     'allow_all_config_required_docs',
--     'anon_validate_code',
--     'anon_mark_used'
--   );
-- Resultado esperado: 0 filas.
