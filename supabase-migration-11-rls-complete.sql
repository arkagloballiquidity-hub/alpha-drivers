-- ALPHA DRIVERS — Migration 11: cerrar últimos agujeros RLS + limpiar {public}
-- Fecha: 2026-08-12
-- Ejecutar en: Supabase Dashboard → SQL Editor (proyecto fggchwkbvelqiofkojqn)
-- ══════════════════════════════════════════════════════════════
-- Diagnóstico (consulta de pg_policies sobre el estado EN VIVO):
--
--   AGUJEROS REALES (USING true / WITH CHECK true, rol público = anon):
--     • event_photos.allow_all_event_photos   → anon lee/escribe/borra
--     • member_benefits.allow_all_member_benefits → anon lee/escribe/borra
--   Estas dos políticas se crearon a mano en la consola (no están en
--   ninguna migración del repo) y nunca se eliminaron.
--
--   POLÍTICAS member_own_* en rol {public}: NO son un agujero — su
--   condición exige auth.uid()/member_id del dueño, y para un anónimo
--   auth.uid() es NULL, así que no ven ni escriben nada. Pero están en
--   {public} en vez de {authenticated}. Se endurecen a authenticated
--   (misma lógica de dueño) como defensa en profundidad. NO se eliminan
--   para no quitarle al miembro la gestión de sus propios registros.
--
--   applications.anon_insert_application ({anon}, INSERT, check=true):
--     intencional — es el formulario público de solicitud. Anon solo
--     puede INSERTAR, no leer. Se deja como está.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Eliminar los dos agujeros abiertos a anon ─────────────
DROP POLICY IF EXISTS allow_all_event_photos    ON event_photos;
DROP POLICY IF EXISTS allow_all_member_benefits ON member_benefits;


-- ── 2. Endurecer políticas de auto-gestión: {public} → authenticated
--    (misma condición de dueño; excluye al rol anónimo a nivel de rol)
ALTER POLICY member_own_benefits ON benefit_requests TO authenticated;
ALTER POLICY member_own_docs     ON member_documents TO authenticated;
ALTER POLICY member_own_payments ON payment_proofs   TO authenticated;
ALTER POLICY member_own_row      ON member_users     TO authenticated;
ALTER POLICY member_own_profile  ON members          TO authenticated;
ALTER POLICY member_own_update   ON members          TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- VERIFICACIÓN — debe devolver 0 filas (ninguna política abierta a
-- anon/public ni con qual = true).
-- ══════════════════════════════════════════════════════════════
-- SELECT tablename, policyname, roles, cmd
-- FROM pg_policies
-- WHERE schemaname='public'
--   AND (qual = 'true' OR '{public}'::name[] && roles::name[])
-- ORDER BY tablename;
