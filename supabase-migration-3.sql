-- ALPHA DRIVERS — Migration 3
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/fggchwkbvelqiofkojqn/sql

-- 1. Add must_change_password column to member_users
ALTER TABLE member_users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT true;

-- 2. Invite codes for membership applications
CREATE TABLE IF NOT EXISTS invite_codes (
  id TEXT PRIMARY KEY DEFAULT ('ic' || floor(extract(epoch from now()) * 1000)::text),
  code TEXT UNIQUE NOT NULL,
  created_by TEXT NOT NULL DEFAULT 'admin',
  used BOOLEAN NOT NULL DEFAULT false,
  used_by TEXT DEFAULT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE invite_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_invite_codes ON invite_codes;
CREATE POLICY allow_all_invite_codes ON invite_codes FOR ALL USING (true) WITH CHECK (true);

-- 3. Member-uploaded documents (admin reviews them)
CREATE TABLE IF NOT EXISTS member_documents (
  id TEXT PRIMARY KEY,
  member_id TEXT,
  member_name TEXT,
  filename TEXT NOT NULL,
  file_type TEXT DEFAULT 'application/octet-stream',
  file_data TEXT NOT NULL,
  doc_type TEXT DEFAULT 'Otro',
  status TEXT DEFAULT 'Pendiente',
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  admin_nota TEXT DEFAULT ''
);
ALTER TABLE member_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_member_docs ON member_documents;
CREATE POLICY allow_all_member_docs ON member_documents FOR ALL USING (true) WITH CHECK (true);

-- 4. Payment proofs (member uploads → admin approves)
CREATE TABLE IF NOT EXISTS payment_proofs (
  id TEXT PRIMARY KEY,
  member_id TEXT,
  member_name TEXT,
  filename TEXT,
  file_type TEXT DEFAULT 'application/octet-stream',
  file_data TEXT NOT NULL,
  status TEXT DEFAULT 'Pendiente',
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  admin_nota TEXT DEFAULT ''
);
ALTER TABLE payment_proofs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS allow_all_payment_proofs ON payment_proofs;
CREATE POLICY allow_all_payment_proofs ON payment_proofs FOR ALL USING (true) WITH CHECK (true);
