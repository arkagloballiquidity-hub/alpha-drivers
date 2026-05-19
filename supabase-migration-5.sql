-- ALPHA DRIVERS — Migration 5
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/fggchwkbvelqiofkojqn/sql

-- 1. Documentos personalizados por miembro
CREATE TABLE IF NOT EXISTS member_required_docs (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL,
  name TEXT NOT NULL,
  descripcion TEXT DEFAULT '',
  activo BOOLEAN DEFAULT true,
  orden INT DEFAULT 0
);
ALTER TABLE member_required_docs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_member_required_docs ON member_required_docs;
CREATE POLICY allow_all_member_required_docs ON member_required_docs FOR ALL USING (true) WITH CHECK (true);

-- 2. Tipos de beneficio configurables
CREATE TABLE IF NOT EXISTS config_benefit_types (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  descripcion TEXT DEFAULT '',
  unit TEXT DEFAULT 'MXN',
  activo BOOLEAN DEFAULT true,
  orden INT DEFAULT 0
);
ALTER TABLE config_benefit_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_config_benefit_types ON config_benefit_types;
CREATE POLICY allow_all_config_benefit_types ON config_benefit_types FOR ALL USING (true) WITH CHECK (true);

-- 3. Límites de beneficios por tipo y nivel
CREATE TABLE IF NOT EXISTS config_benefit_limits (
  id TEXT PRIMARY KEY,
  benefit_type_id TEXT NOT NULL,
  nivel TEXT NOT NULL,
  max_amount NUMERIC DEFAULT 0
);
ALTER TABLE config_benefit_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_config_benefit_limits ON config_benefit_limits;
CREATE POLICY allow_all_config_benefit_limits ON config_benefit_limits FOR ALL USING (true) WITH CHECK (true);
