-- ALPHA DRIVERS — Migration 12: trigger anti-escalación más robusto
-- Fecha: 2026-08-13
-- Ejecutar en: Supabase Dashboard → SQL Editor (proyecto fggchwkbvelqiofkojqn)
-- ══════════════════════════════════════════════════════════════
-- Migration 9 congelaba las columnas privilegiadas de `members` solo
-- cuando el claim de rol era exactamente 'member'. Un principal con
-- member_id pero rol ausente o distinto no quedaba protegido.
-- Se cambia la condición a "cualquier no-staff", de modo que solo
-- admin/concierge/staff pueden tocar nivel/status/numero/benefits_start/
-- email. Staff mantiene control total (la condición es falsa para ellos).
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION _protect_member_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT _ad_is_staff() THEN
    NEW.nivel          := OLD.nivel;
    NEW.status         := OLD.status;
    NEW.numero         := OLD.numero;
    NEW.benefits_start := OLD.benefits_start;
    NEW.email          := OLD.email;
  END IF;
  RETURN NEW;
END;
$$;

-- El trigger `protect_member_fields` (migration 9) ya apunta a esta función;
-- CREATE OR REPLACE basta, no hace falta recrear el trigger.
