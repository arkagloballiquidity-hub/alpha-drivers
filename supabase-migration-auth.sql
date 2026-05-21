-- ─────────────────────────────────────────────────────────────
-- ALPHA DRIVERS — Migración a Supabase Auth
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- ─────────────────────────────────────────────────────────────

-- 1. Agregar columna auth_user_id a member_users
--    (vincula cada miembro con su cuenta en auth.users)
ALTER TABLE member_users
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Eliminar columna de contraseña en texto plano (HACER AL FINAL)
--    Primero migrar todos los miembros, luego ejecutar esta línea:
-- ALTER TABLE member_users DROP COLUMN IF EXISTS password;

-- 3. Agregar columna must_change_password si no existe
ALTER TABLE member_users
  ADD COLUMN IF NOT EXISTS must_change_password boolean DEFAULT true;

-- 4. Crear cuenta de admin en Supabase Auth
--    NO hacer desde aquí — hacerlo desde el admin panel de Supabase:
--    Dashboard → Authentication → Users → Add User
--    Email: admin@alphadrivers.mx
--    Password: (una contraseña fuerte de tu elección)
--    Luego en SQL Editor ejecutar esto para asignar el rol:
--
-- UPDATE auth.users
--   SET raw_user_meta_data = raw_user_meta_data || '{"role":"admin","display_name":"admin"}'
--   WHERE email = 'admin@alphadrivers.mx';

-- 5. Para staff/concierge existentes en admin_users, crear sus cuentas Auth manualmente:
--    Dashboard → Authentication → Users → Add User
--    Email: suNombreDeUsuario@alphadrivers.mx
--    Luego asignar rol en raw_user_meta_data igual que el paso 4,
--    usando "role":"concierge" o "role":"staff" según corresponda.

-- 6. (Opcional, después de migrar todo) Endurecer RLS en member_users:
--    Eliminar la política permisiva actual y crear una basada en auth.uid()

-- Eliminar política permisiva
-- DROP POLICY IF EXISTS "allow_all" ON member_users;

-- Solo el propio miembro puede leer su fila; admins ven todo vía service_role
-- CREATE POLICY "member_read_own" ON member_users
--   FOR SELECT USING (
--     auth_user_id = auth.uid()
--   );
