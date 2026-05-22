-- ─────────────────────────────────────────────────────────────
-- ALPHA DRIVERS — Migration 6: RLS + concierge_requests + admin must_change_password
-- Ejecutar en: https://supabase.com/dashboard/project/fggchwkbvelqiofkojqn/sql
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- 0. FUNCIONES AUXILIARES
--    Leen desde app_metadata (solo escribible por service role)
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION _ad_role()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(auth.jwt()->'app_metadata'->>'role', '');
$$;

CREATE OR REPLACE FUNCTION _ad_member_id()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(auth.jwt()->'app_metadata'->>'member_id', '');
$$;

CREATE OR REPLACE FUNCTION _ad_is_staff()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT _ad_role() IN ('admin', 'concierge', 'staff');
$$;

CREATE OR REPLACE FUNCTION _ad_is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT _ad_role() = 'admin';
$$;

-- ══════════════════════════════════════════════════════════════
-- 1. NUEVA TABLA: concierge_requests
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS concierge_requests (
  id          TEXT PRIMARY KEY,
  member_id   TEXT NOT NULL,
  member_name TEXT DEFAULT '',
  categoria   TEXT DEFAULT 'General',
  mensaje     TEXT NOT NULL,
  status      TEXT DEFAULT 'Pendiente',
  admin_nota  TEXT DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════
-- 2. COLUMNA must_change_password EN admin_users
--    (mueve el flag de user_metadata -escribible por el usuario-
--     a la tabla que solo el service role puede modificar)
-- ══════════════════════════════════════════════════════════════

ALTER TABLE admin_users
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT false;

-- Migrar el flag desde user_metadata de auth.users para cuentas existentes
-- (solo si ya tienes staff creado; si no, esta query no hace nada)
UPDATE admin_users au
SET    must_change_password = true
FROM   auth.users u
WHERE  au.auth_user_id = u.id
AND    (u.raw_user_meta_data->>'must_change_password')::boolean IS TRUE
AND    au.must_change_password = false;

-- ══════════════════════════════════════════════════════════════
-- 3. RLS — TABLAS SENSIBLES (PII / financieras)
-- ══════════════════════════════════════════════════════════════

-- ── members ──────────────────────────────────────────────────
ALTER TABLE members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_members"        ON members;
DROP POLICY IF EXISTS "member_select_own"         ON members;
DROP POLICY IF EXISTS "member_update_own"         ON members;
DROP POLICY IF EXISTS allow_all                   ON members;

CREATE POLICY "staff_all_members" ON members
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_own" ON members
  FOR SELECT TO authenticated
  USING (id = _ad_member_id());

CREATE POLICY "member_update_own" ON members
  FOR UPDATE TO authenticated
  USING     (id = _ad_member_id())
  WITH CHECK (id = _ad_member_id());

-- ── benefit_requests ─────────────────────────────────────────
ALTER TABLE benefit_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_benefit_requests"    ON benefit_requests;
DROP POLICY IF EXISTS "member_select_benefit_requests" ON benefit_requests;
DROP POLICY IF EXISTS "member_insert_benefit_requests" ON benefit_requests;
DROP POLICY IF EXISTS allow_all                        ON benefit_requests;

CREATE POLICY "staff_all_benefit_requests" ON benefit_requests
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_benefit_requests" ON benefit_requests
  FOR SELECT TO authenticated
  USING (member_id = _ad_member_id());

CREATE POLICY "member_insert_benefit_requests" ON benefit_requests
  FOR INSERT TO authenticated
  WITH CHECK (member_id = _ad_member_id());

-- ── member_documents ─────────────────────────────────────────
ALTER TABLE member_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_member_documents"    ON member_documents;
DROP POLICY IF EXISTS "member_select_member_documents" ON member_documents;
DROP POLICY IF EXISTS "member_insert_member_documents" ON member_documents;
DROP POLICY IF EXISTS allow_all                        ON member_documents;

CREATE POLICY "staff_all_member_documents" ON member_documents
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_member_documents" ON member_documents
  FOR SELECT TO authenticated
  USING (member_id = _ad_member_id());

CREATE POLICY "member_insert_member_documents" ON member_documents
  FOR INSERT TO authenticated
  WITH CHECK (member_id = _ad_member_id());

-- ── payment_proofs ────────────────────────────────────────────
ALTER TABLE payment_proofs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_payment_proofs"    ON payment_proofs;
DROP POLICY IF EXISTS "member_select_payment_proofs" ON payment_proofs;
DROP POLICY IF EXISTS "member_insert_payment_proofs" ON payment_proofs;
DROP POLICY IF EXISTS allow_all                      ON payment_proofs;

CREATE POLICY "staff_all_payment_proofs" ON payment_proofs
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_payment_proofs" ON payment_proofs
  FOR SELECT TO authenticated
  USING (member_id = _ad_member_id());

CREATE POLICY "member_insert_payment_proofs" ON payment_proofs
  FOR INSERT TO authenticated
  WITH CHECK (member_id = _ad_member_id());

-- ── member_users ──────────────────────────────────────────────
ALTER TABLE member_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_member_users"  ON member_users;
DROP POLICY IF EXISTS "member_select_own_user"  ON member_users;
DROP POLICY IF EXISTS "member_update_own_user"  ON member_users;
DROP POLICY IF EXISTS allow_all                 ON member_users;

CREATE POLICY "staff_all_member_users" ON member_users
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

-- El miembro puede leer y actualizar su propio registro (ej: must_change_password)
CREATE POLICY "member_select_own_user" ON member_users
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

CREATE POLICY "member_update_own_user" ON member_users
  FOR UPDATE TO authenticated
  USING     (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- ── admin_users ───────────────────────────────────────────────
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_admin_users"   ON admin_users;
DROP POLICY IF EXISTS "staff_select_own_admin"  ON admin_users;
DROP POLICY IF EXISTS "staff_update_own_admin"  ON admin_users;
DROP POLICY IF EXISTS allow_all                 ON admin_users;

-- Solo admins pueden ver y gestionar todo el staff
CREATE POLICY "admin_all_admin_users" ON admin_users
  FOR ALL TO authenticated
  USING  (_ad_is_admin())
  WITH CHECK (_ad_is_admin());

-- Concierge/staff pueden leer y actualizar su propia fila (para must_change_password)
CREATE POLICY "staff_select_own_admin" ON admin_users
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

CREATE POLICY "staff_update_own_admin" ON admin_users
  FOR UPDATE TO authenticated
  USING     (auth_user_id = auth.uid() AND NOT _ad_is_admin())
  -- Solo puede actualizar must_change_password — no puede cambiar su propio rol
  WITH CHECK (auth_user_id = auth.uid() AND NOT _ad_is_admin());

-- ── invite_codes ──────────────────────────────────────────────
ALTER TABLE invite_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_invite_codes"     ON invite_codes;
DROP POLICY IF EXISTS "member_select_own_codes"    ON invite_codes;
DROP POLICY IF EXISTS "member_insert_own_codes"    ON invite_codes;
DROP POLICY IF EXISTS "anon_validate_code"         ON invite_codes;
DROP POLICY IF EXISTS "anon_mark_used"             ON invite_codes;
DROP POLICY IF EXISTS allow_all                    ON invite_codes;

CREATE POLICY "staff_all_invite_codes" ON invite_codes
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_own_codes" ON invite_codes
  FOR SELECT TO authenticated
  USING (referred_by = _ad_member_id());

CREATE POLICY "member_insert_own_codes" ON invite_codes
  FOR INSERT TO authenticated
  WITH CHECK (referred_by = _ad_member_id());

-- Anon (landing page sin login) solo puede leer para validar un código por valor exacto
CREATE POLICY "anon_validate_code" ON invite_codes
  FOR SELECT TO anon
  USING (true);   -- el filtro .eq('code',X).eq('used',false) lo aplica el cliente

-- Anon puede marcar un código como usado al registrar solicitud
-- Solo permite cambiar used de false → true; nada más
CREATE POLICY "anon_mark_used" ON invite_codes
  FOR UPDATE TO anon
  USING     (used = false)
  WITH CHECK (used = true);

-- ── applications ──────────────────────────────────────────────
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_applications"  ON applications;
DROP POLICY IF EXISTS "anon_insert_application" ON applications;
DROP POLICY IF EXISTS allow_all                 ON applications;

CREATE POLICY "staff_all_applications" ON applications
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

-- Solo INSERT público (nadie sin credenciales puede leer solicitudes)
CREATE POLICY "anon_insert_application" ON applications
  FOR INSERT TO anon
  WITH CHECK (true);

-- ── concierge_requests ────────────────────────────────────────
ALTER TABLE concierge_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_concierge_requests"    ON concierge_requests;
DROP POLICY IF EXISTS "member_select_concierge_requests" ON concierge_requests;
DROP POLICY IF EXISTS "member_insert_concierge_requests" ON concierge_requests;

CREATE POLICY "staff_all_concierge_requests" ON concierge_requests
  FOR ALL TO authenticated
  USING  (_ad_is_staff())
  WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_concierge_requests" ON concierge_requests
  FOR SELECT TO authenticated
  USING (member_id = _ad_member_id());

CREATE POLICY "member_insert_concierge_requests" ON concierge_requests
  FOR INSERT TO authenticated
  WITH CHECK (member_id = _ad_member_id());

-- ══════════════════════════════════════════════════════════════
-- 4. RLS — TABLAS DE CONFIG (solo lectura para miembros)
-- ══════════════════════════════════════════════════════════════

-- ── config_required_docs ──────────────────────────────────────
ALTER TABLE config_required_docs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_req_docs"    ON config_required_docs;
DROP POLICY IF EXISTS "member_select_req_docs" ON config_required_docs;
DROP POLICY IF EXISTS allow_all_member_required_docs ON config_required_docs;
DROP POLICY IF EXISTS allow_all               ON config_required_docs;

CREATE POLICY "staff_all_req_docs" ON config_required_docs
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_req_docs" ON config_required_docs
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── config_general ────────────────────────────────────────────
ALTER TABLE config_general ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_config_general"    ON config_general;
DROP POLICY IF EXISTS "member_select_config_general" ON config_general;
DROP POLICY IF EXISTS allow_all                      ON config_general;

CREATE POLICY "staff_all_config_general" ON config_general
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_config_general" ON config_general
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── config_concierge ──────────────────────────────────────────
ALTER TABLE config_concierge ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_config_concierge"    ON config_concierge;
DROP POLICY IF EXISTS "member_select_config_concierge" ON config_concierge;
DROP POLICY IF EXISTS allow_all                        ON config_concierge;

CREATE POLICY "staff_all_config_concierge" ON config_concierge
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_config_concierge" ON config_concierge
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── config_limites ────────────────────────────────────────────
ALTER TABLE config_limites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_config_limites"    ON config_limites;
DROP POLICY IF EXISTS "member_select_config_limites" ON config_limites;
DROP POLICY IF EXISTS allow_all                      ON config_limites;

CREATE POLICY "staff_all_config_limites" ON config_limites
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_config_limites" ON config_limites
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── config_benefit_types ──────────────────────────────────────
ALTER TABLE config_benefit_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_config_benefit_types"    ON config_benefit_types;
DROP POLICY IF EXISTS "member_select_config_benefit_types" ON config_benefit_types;
DROP POLICY IF EXISTS allow_all_config_benefit_types       ON config_benefit_types;
DROP POLICY IF EXISTS allow_all                            ON config_benefit_types;

CREATE POLICY "staff_all_config_benefit_types" ON config_benefit_types
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_config_benefit_types" ON config_benefit_types
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── config_benefit_limits ────────────────────────────────────
ALTER TABLE config_benefit_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_config_benefit_limits"    ON config_benefit_limits;
DROP POLICY IF EXISTS "member_select_config_benefit_limits" ON config_benefit_limits;
DROP POLICY IF EXISTS allow_all_config_benefit_limits       ON config_benefit_limits;
DROP POLICY IF EXISTS allow_all                             ON config_benefit_limits;

CREATE POLICY "staff_all_config_benefit_limits" ON config_benefit_limits
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_config_benefit_limits" ON config_benefit_limits
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── socios ────────────────────────────────────────────────────
ALTER TABLE socios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_socios"    ON socios;
DROP POLICY IF EXISTS "member_select_socios" ON socios;
DROP POLICY IF EXISTS allow_all             ON socios;

CREATE POLICY "staff_all_socios" ON socios
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_socios" ON socios
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── road_tours ────────────────────────────────────────────────
ALTER TABLE road_tours ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_road_tours"    ON road_tours;
DROP POLICY IF EXISTS "member_select_road_tours" ON road_tours;
DROP POLICY IF EXISTS allow_all                  ON road_tours;

CREATE POLICY "staff_all_road_tours" ON road_tours
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_road_tours" ON road_tours
  FOR SELECT TO authenticated USING (_ad_role() = 'member');

-- ── event_photos ──────────────────────────────────────────────
ALTER TABLE event_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_event_photos"    ON event_photos;
DROP POLICY IF EXISTS "member_select_event_photos" ON event_photos;
DROP POLICY IF EXISTS allow_all                    ON event_photos;

CREATE POLICY "staff_all_event_photos" ON event_photos
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_event_photos" ON event_photos
  FOR SELECT TO authenticated USING (member_id = _ad_member_id());

-- ── member_required_docs ──────────────────────────────────────
ALTER TABLE member_required_docs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_member_req_docs"    ON member_required_docs;
DROP POLICY IF EXISTS "member_select_member_req_docs" ON member_required_docs;
DROP POLICY IF EXISTS allow_all_member_required_docs  ON member_required_docs;
DROP POLICY IF EXISTS allow_all                        ON member_required_docs;

CREATE POLICY "staff_all_member_req_docs" ON member_required_docs
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_member_req_docs" ON member_required_docs
  FOR SELECT TO authenticated USING (member_id = _ad_member_id());

-- ── member_benefits ───────────────────────────────────────────
ALTER TABLE member_benefits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_all_member_benefits"    ON member_benefits;
DROP POLICY IF EXISTS "member_select_member_benefits" ON member_benefits;
DROP POLICY IF EXISTS allow_all                       ON member_benefits;

CREATE POLICY "staff_all_member_benefits" ON member_benefits
  FOR ALL TO authenticated USING (_ad_is_staff()) WITH CHECK (_ad_is_staff());

CREATE POLICY "member_select_member_benefits" ON member_benefits
  FOR SELECT TO authenticated USING (member_id = _ad_member_id());
