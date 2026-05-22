-- ALPHA DRIVERS — Migration 7: Hardening de columnas y config sensibles
-- Fecha: 2026-05-22
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════
-- Qué corrige:
--   1. config_general  → solo admin puede escribir (evita que concierge
--      modifique sus propios permisos de menú desde consola del navegador)
--   2. config_limites  → solo admin puede escribir (evita cambiar límites
--      de beneficios de miembros)
--   3. config_benefit_types / config_benefit_limits → solo admin escribe
--   4. config_required_docs → solo admin escribe
--   5. Trigger en admin_users: un concierge/staff solo puede cambiar
--      must_change_password en su fila, no role/username/active/name
--   6. Trigger en member_users: un miembro solo puede cambiar
--      must_change_password, no member_id/username/active/auth_user_id
-- ══════════════════════════════════════════════════════════════


-- ── 1. config_general — solo admin escribe ───────────────────
DROP POLICY IF EXISTS "staff_all_config_general"    ON config_general;
DROP POLICY IF EXISTS "admin_write_config_general"  ON config_general;
DROP POLICY IF EXISTS "staff_read_config_general"   ON config_general;

CREATE POLICY "admin_write_config_general" ON config_general
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

-- concierge y staff pueden leer (necesitan contract_url, etc.)
CREATE POLICY "staff_read_config_general" ON config_general
  FOR SELECT TO authenticated
  USING (_ad_is_staff());
-- (member_select_config_general de migration-6 se mantiene intacta)


-- ── 2. config_limites — solo admin escribe ───────────────────
DROP POLICY IF EXISTS "staff_all_config_limites"    ON config_limites;
DROP POLICY IF EXISTS "admin_write_config_limites"  ON config_limites;
DROP POLICY IF EXISTS "staff_read_config_limites"   ON config_limites;

CREATE POLICY "admin_write_config_limites" ON config_limites
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

CREATE POLICY "staff_read_config_limites" ON config_limites
  FOR SELECT TO authenticated
  USING (_ad_is_staff());


-- ── 3. config_benefit_types — solo admin escribe ─────────────
DROP POLICY IF EXISTS "staff_all_ben_types"        ON config_benefit_types;
DROP POLICY IF EXISTS "admin_write_ben_types"      ON config_benefit_types;
DROP POLICY IF EXISTS "staff_read_ben_types"       ON config_benefit_types;

CREATE POLICY "admin_write_ben_types" ON config_benefit_types
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

CREATE POLICY "staff_read_ben_types" ON config_benefit_types
  FOR SELECT TO authenticated
  USING (_ad_is_staff());


-- ── 4. config_benefit_limits — solo admin escribe ────────────
DROP POLICY IF EXISTS "staff_all_ben_limits"       ON config_benefit_limits;
DROP POLICY IF EXISTS "admin_write_ben_limits"     ON config_benefit_limits;
DROP POLICY IF EXISTS "staff_read_ben_limits"      ON config_benefit_limits;

CREATE POLICY "admin_write_ben_limits" ON config_benefit_limits
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

CREATE POLICY "staff_read_ben_limits" ON config_benefit_limits
  FOR SELECT TO authenticated
  USING (_ad_is_staff());


-- ── 5. config_required_docs — solo admin escribe ─────────────
DROP POLICY IF EXISTS "staff_all_req_docs"         ON config_required_docs;
DROP POLICY IF EXISTS "admin_write_req_docs"       ON config_required_docs;
DROP POLICY IF EXISTS "staff_read_req_docs"        ON config_required_docs;

CREATE POLICY "admin_write_req_docs" ON config_required_docs
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

CREATE POLICY "staff_read_req_docs" ON config_required_docs
  FOR SELECT TO authenticated
  USING (_ad_is_staff());


-- ── 6. Trigger: admin_users — proteger columnas sensibles ────
-- Concierge/staff solo pueden cambiar must_change_password en su fila.
-- No pueden cambiar role, username, active, name ni auth_user_id.

CREATE OR REPLACE FUNCTION _protect_admin_user_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.jwt()->'app_metadata'->>'role' != 'admin' THEN
    NEW.role         := OLD.role;
    NEW.username     := OLD.username;
    NEW.active       := OLD.active;
    NEW.name         := OLD.name;
    NEW.auth_user_id := OLD.auth_user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_admin_user_fields ON admin_users;
CREATE TRIGGER protect_admin_user_fields
  BEFORE UPDATE ON admin_users
  FOR EACH ROW EXECUTE FUNCTION _protect_admin_user_fields();


-- ── 7. Trigger: member_users — proteger columnas sensibles ───
-- Miembros solo pueden cambiar must_change_password en su fila.
-- No pueden cambiar member_id, username, active ni auth_user_id.

CREATE OR REPLACE FUNCTION _protect_member_user_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.jwt()->'app_metadata'->>'role' = 'member' THEN
    NEW.member_id    := OLD.member_id;
    NEW.username     := OLD.username;
    NEW.active       := OLD.active;
    NEW.auth_user_id := OLD.auth_user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_member_user_fields ON member_users;
CREATE TRIGGER protect_member_user_fields
  BEFORE UPDATE ON member_users
  FOR EACH ROW EXECUTE FUNCTION _protect_member_user_fields();


-- ══════════════════════════════════════════════════════════════
-- VERIFICAR (ejecutar después si quieres confirmar)
-- ══════════════════════════════════════════════════════════════
-- SELECT tablename, policyname, cmd
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('config_general','config_limites','config_benefit_types',
--                     'config_benefit_limits','config_required_docs',
--                     'admin_users','member_users')
-- ORDER BY tablename, policyname;
