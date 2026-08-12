-- ALPHA DRIVERS — Migration 9: Security fix (RLS bypass + privilege escalation)
-- Fecha: 2026-08-12
-- Ejecutar en: Supabase Dashboard → SQL Editor (proyecto fggchwkbvelqiofkojqn)
-- ══════════════════════════════════════════════════════════════
-- CONTEXTO — auditoría de seguridad:
--   Migraciones 3–5 crearon políticas permisivas `allow_all_<tabla>`
--   (FOR ALL USING(true) WITH CHECK(true), aplicadas a PUBLIC = anon).
--   Migración 6 intentó reemplazarlas pero hizo DROP del nombre
--   equivocado (`allow_all` en vez de `allow_all_<tabla>`), por lo que
--   varias políticas permisivas SOBREVIVIERON. Como Postgres combina
--   políticas permisivas con OR, estas anulan las políticas restrictivas
--   y dejan las tablas accesibles al rol anónimo.
--
--   Tablas afectadas (política permisiva nunca eliminada):
--     • member_documents   → CRÍTICO (docs de identidad / KYC, contratos)
--     • payment_proofs      → CRÍTICO (comprobantes financieros)
--     • invite_codes        → ALTO   (bypass del acceso por invitación + PII)
--     • config_general      → MEDIO  (envenenamiento de contract_url)
--     • config_required_docs→ MEDIO  (lo arregla migración 8, se re-aplica)
--
--   Adicional: la política `member_update_own` permite a un miembro
--   sobrescribir CUALQUIER columna de su fila (nivel, status, numero,
--   benefits_start, email) → auto-escalación de membresía. Se añade un
--   trigger que solo permite editar name/phone/city/vehicle/bio/avatar_data.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Eliminar políticas permisivas sobrevivientes ──────────
DROP POLICY IF EXISTS allow_all_member_docs         ON member_documents;
DROP POLICY IF EXISTS allow_all_payment_proofs      ON payment_proofs;
DROP POLICY IF EXISTS allow_all_invite_codes        ON invite_codes;
DROP POLICY IF EXISTS allow_all_config_general      ON config_general;
DROP POLICY IF EXISTS allow_all_config_required_docs ON config_required_docs;

-- Por si alguna quedó con el nombre corto en algún entorno:
DROP POLICY IF EXISTS allow_all ON member_documents;
DROP POLICY IF EXISTS allow_all ON payment_proofs;
DROP POLICY IF EXISTS allow_all ON invite_codes;
DROP POLICY IF EXISTS allow_all ON config_general;
DROP POLICY IF EXISTS allow_all ON config_required_docs;


-- ── 2. Trigger: members — proteger columnas privilegiadas ────
-- Un miembro solo puede editar name/phone/city/vehicle/bio/avatar_data.
-- No puede cambiar nivel, status, numero, benefits_start ni email.
CREATE OR REPLACE FUNCTION _protect_member_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.jwt()->'app_metadata'->>'role' = 'member' THEN
    NEW.nivel          := OLD.nivel;
    NEW.status         := OLD.status;
    NEW.numero         := OLD.numero;
    NEW.benefits_start := OLD.benefits_start;
    NEW.email          := OLD.email;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_member_fields ON members;
CREATE TRIGGER protect_member_fields
  BEFORE UPDATE ON members
  FOR EACH ROW EXECUTE FUNCTION _protect_member_fields();


-- ══════════════════════════════════════════════════════════════
-- VERIFICACIÓN — ejecutar y confirmar que NO aparece ninguna
-- política con qual = true ni el rol {public} en estas tablas.
-- ══════════════════════════════════════════════════════════════
-- SELECT tablename, policyname, roles, cmd, qual
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('member_documents','payment_proofs','invite_codes',
--                     'config_general','config_required_docs','members')
-- ORDER BY tablename, policyname;
--
-- Barrido global: cualquier política todavía abierta a anon/PUBLIC
-- SELECT tablename, policyname, roles, cmd
-- FROM pg_policies
-- WHERE schemaname='public'
--   AND (qual = 'true' OR '{public}'::name[] && roles::name[])
-- ORDER BY tablename;
