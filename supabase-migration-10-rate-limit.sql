-- ALPHA DRIVERS — Migration 10: Rate limiting compartido (multi-instancia)
-- Fecha: 2026-08-12
-- Ejecutar en: Supabase Dashboard → SQL Editor (proyecto fggchwkbvelqiofkojqn)
-- ══════════════════════════════════════════════════════════════
-- Por qué: el rate limiting en memoria de las funciones serverless se
-- reinicia por instancia (Vercel corre varias), así que el límite real
-- es mucho más alto del configurado. Este contador vive en la base y es
-- global a todas las instancias. Lo consume el service role vía RPC.
-- ══════════════════════════════════════════════════════════════

create table if not exists rate_limits (
  key       text primary key,
  count     integer not null default 0,
  reset_at  timestamptz not null
);

-- RLS activo y SIN políticas: solo el service role (que ignora RLS) accede.
alter table rate_limits enable row level security;

-- Contador atómico: incrementa y devuelve si sigue bajo el límite.
create or replace function check_rate_limit(p_key text, p_max int, p_window_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now   timestamptz := now();
  v_count integer;
begin
  insert into rate_limits as r (key, count, reset_at)
    values (p_key, 1, v_now + make_interval(secs => p_window_seconds))
  on conflict (key) do update
    set count    = case when r.reset_at < v_now then 1 else r.count + 1 end,
        reset_at = case when r.reset_at < v_now then v_now + make_interval(secs => p_window_seconds)
                        else r.reset_at end
  returning r.count into v_count;
  return v_count <= p_max;
end;
$$;

-- Solo el service role puede llamarla (evita abuso con la anon key).
revoke execute on function check_rate_limit(text, int, int) from public;
grant  execute on function check_rate_limit(text, int, int) to service_role;

-- Limpieza opcional de llaves viejas (correr de vez en cuando, o con un cron):
-- DELETE FROM rate_limits WHERE reset_at < now() - interval '1 day';
