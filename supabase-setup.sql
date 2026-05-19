-- ─────────────────────────────────────────────────────────────
-- ALPHA DRIVERS — Supabase Schema Setup
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- ─────────────────────────────────────────────────────────────

-- MEMBERS
create table if not exists members (
  id text primary key,
  name text not null,
  email text default '',
  city text default '',
  vehicle text default '',
  nivel text default 'Alpha Premium',
  date text default '',
  status text default 'Activo',
  created_at timestamptz default now()
);

-- MEMBER PORTAL CREDENTIALS
create table if not exists member_users (
  id uuid primary key default gen_random_uuid(),
  member_id text references members(id) on delete cascade,
  username text unique not null,
  password text not null,
  active boolean default true,
  created_at timestamptz default now()
);

-- MEMBERSHIP APPLICATIONS
create table if not exists applications (
  id text primary key,
  name text not null,
  email text default '',
  city text default '',
  vehicle text default '',
  date text default '',
  status text default 'En revisión',
  msg text default '',
  created_at timestamptz default now()
);

-- BENEFIT REQUESTS
create table if not exists benefit_requests (
  id text primary key,
  member_id text,
  member_name text,
  tipo text,
  detalle text,
  monto numeric,
  notas text,
  status text default 'Pendiente',
  fecha text,
  admin_nota text default '',
  pay_method text,
  pay_details jsonb,
  sv_fecha text,
  sv_desc text,
  sv_socio_nombre text,
  created_at timestamptz default now()
);

-- SOCIOS & TALLERES
create table if not exists socios (
  id text primary key,
  nombre text not null,
  categoria text default 'Otro',
  limite numeric default 0,
  contacto text default '',
  notas text default '',
  created_at timestamptz default now()
);

-- ROAD TOURS
create table if not exists road_tours (
  id text primary key,
  fecha text,
  ruta text,
  cupo integer default 20,
  inscritos integer default 0,
  created_at timestamptz default now()
);

-- BENEFIT LIMITS CONFIG
create table if not exists config_limites (
  nivel text primary key,
  efectivo numeric not null default 0,
  servicio numeric not null default 0
);

-- ─── SEED DATA ────────────────────────────────────────────────

insert into config_limites (nivel, efectivo, servicio) values
  ('Alpha Premium', 150000, 50000),
  ('Alpha', 100000, 30000)
on conflict (nivel) do nothing;

insert into socios (id, nombre, categoria, limite, contacto, notas) values
  ('s1', 'Porsche Service Center CDMX', 'Taller Oficial', 50000, 'service@porsche.mx', ''),
  ('s2', 'Ferrari Maserati México', 'Taller Oficial', 50000, 'service@ferrarimax.mx', ''),
  ('s3', 'AutoDetail Elite Polanco', 'Detailing & Estética', 15000, 'hola@autodetailite.mx', 'Cita previa requerida'),
  ('s4', 'Taller McLaren México', 'Taller Oficial', 50000, 'service@mclarenmexico.com', ''),
  ('s5', 'Sushi Ammo Polanco', 'Restaurante', 5000, 'reservas@sushiammo.com', 'Máx $5K por visita'),
  ('s6', 'Hyatt Regency CDMX', 'Hospedaje', 20000, 'grupos@hyatt.mx', 'Disponible vía concierge')
on conflict (id) do nothing;

insert into road_tours (id, fecha, ruta, cupo, inscritos) values
  ('rt1', '14-15 Jun 2025', 'CDMX → Guadalajara', 20, 12),
  ('rt2', '19-20 Jul 2025', 'CDMX → Valle de Bravo', 20, 6),
  ('rt3', '23-24 Ago 2025', 'CDMX → Oaxaca', 20, 2)
on conflict (id) do nothing;

-- ─── ROW LEVEL SECURITY ───────────────────────────────────────
alter table members enable row level security;
alter table member_users enable row level security;
alter table applications enable row level security;
alter table benefit_requests enable row level security;
alter table socios enable row level security;
alter table road_tours enable row level security;
alter table config_limites enable row level security;

create policy "allow_all" on members for all using (true) with check (true);
create policy "allow_all" on member_users for all using (true) with check (true);
create policy "allow_all" on applications for all using (true) with check (true);
create policy "allow_all" on benefit_requests for all using (true) with check (true);
create policy "allow_all" on socios for all using (true) with check (true);
create policy "allow_all" on road_tours for all using (true) with check (true);
create policy "allow_all" on config_limites for all using (true) with check (true);
