-- ALPHA DRIVERS — Migration 4
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/fggchwkbvelqiofkojqn/sql

-- 1. Documentos requeridos configurables
CREATE TABLE IF NOT EXISTS config_required_docs (
  id TEXT PRIMARY KEY DEFAULT ('doc' || floor(extract(epoch from now()) * 1000)::text),
  name TEXT NOT NULL,
  descripcion TEXT DEFAULT '',
  orden INT DEFAULT 0,
  activo BOOLEAN DEFAULT true
);
ALTER TABLE config_required_docs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_config_required_docs ON config_required_docs;
CREATE POLICY allow_all_config_required_docs ON config_required_docs FOR ALL USING (true) WITH CHECK (true);

INSERT INTO config_required_docs (id, name, descripcion, orden) VALUES
  ('doc001', 'Identificación Oficial', 'INE, pasaporte o licencia de conducir vigente', 1),
  ('doc002', 'Comprobante de Domicilio', 'Máximo 3 meses de antigüedad', 2),
  ('doc003', 'Contrato Firmado', 'Contrato de membresía firmado y escaneado', 3)
ON CONFLICT (id) DO NOTHING;

-- 2. Configuración general (contrato, etc.)
CREATE TABLE IF NOT EXISTS config_general (
  key TEXT PRIMARY KEY,
  value TEXT DEFAULT ''
);
ALTER TABLE config_general ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_config_general ON config_general;
CREATE POLICY allow_all_config_general ON config_general FOR ALL USING (true) WITH CHECK (true);

INSERT INTO config_general (key, value) VALUES
  ('contract_url', ''),
  ('contract_filename', 'Contrato_Alpha_Drivers.pdf')
ON CONFLICT (key) DO NOTHING;
