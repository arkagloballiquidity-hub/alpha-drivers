-- ─────────────────────────────────────────────────────────────
-- ALPHA DRIVERS — Migration 2: Staff Users + Concierge Config
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- ─────────────────────────────────────────────────────────────

-- ADMIN / STAFF USERS
create table if not exists admin_users (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  username text unique not null,
  password text not null,
  role text default 'concierge', -- 'admin' | 'concierge'
  active boolean default true,
  created_at timestamptz default now()
);

-- CONCIERGE CONTACT CONFIG (key-value)
create table if not exists config_concierge (
  key text primary key,
  value text not null default ''
);

-- Default values
insert into config_concierge (key, value) values
  ('email',    'concierge@alphadrivers.mx'),
  ('whatsapp', '+52 55 0000 0000'),
  ('horario',  'Lun–Vie · 9am–8pm')
on conflict (key) do nothing;

-- RLS
alter table admin_users enable row level security;
alter table config_concierge enable row level security;
create policy "allow_all" on admin_users for all using (true) with check (true);
create policy "allow_all" on config_concierge for all using (true) with check (true);
