#!/usr/bin/env bash
# Chequeo externo de regresión de seguridad — ALPHA Drivers.
# Solo lectura: barrido anónimo del REST de Supabase + headers/404 del sitio.
# Sale con código != 0 si detecta cualquier regresión. Usa solo la anon key pública.
set -uo pipefail

SB="https://fggchwkbvelqiofkojqn.supabase.co/rest/v1"
SITE="https://www.alphadrivers.mx"
ANON="$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' login.html | head -1)"

fail=0
echo "== ALPHA Drivers — chequeo de seguridad =="
echo

if [ -z "$ANON" ]; then
  echo "ERROR: no se encontró la anon key pública en login.html"
  exit 2
fi

echo "-- RLS: un anónimo debe ver [] en cada tabla sensible --"
for t in member_documents payment_proofs member_benefits event_photos invite_codes members member_users benefit_requests config_general; do
  body="$(curl -s "$SB/$t?select=*&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $ANON")"
  if [ "$body" = "[]" ]; then
    echo "  OK     $t → []"
  elif printf '%s' "$body" | grep -q '"code"\|"message"'; then
    echo "  OK     $t → bloqueado por RLS"
  else
    echo "  FALLA  $t → DEVUELVE DATOS: $(printf '%s' "$body" | cut -c1-80)"
    fail=1
  fi
done

echo
echo "-- Archivos sensibles: deben dar 404 --"
for f in supabase-setup.sql supabase-migration-9-security-fix.sql "ALPHA%20DRIVERS.pdf"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$SITE/$f")"
  if [ "$code" = "404" ]; then echo "  OK     /$f → 404"; else echo "  FALLA  /$f → $code (debería ser 404)"; fail=1; fi
done

echo
echo "-- Headers y disponibilidad --"
hdr="$(curl -sL -D - -o /dev/null "$SITE/admin")"
if printf '%s' "$hdr" | grep -iq "content-security-policy"; then
  if printf '%s' "$hdr" | grep -i "content-security-policy" | grep -iqE "cdn\.jsdelivr\.net|cdnjs"; then
    echo "  FALLA  CSP volvió a permitir CDNs externos"; fail=1
  else
    echo "  OK     CSP presente y sin CDNs"
  fi
else
  echo "  FALLA  CSP ausente en /admin"; fail=1
fi
printf '%s' "$hdr" | grep -iq "strict-transport-security" && echo "  OK     HSTS presente" || { echo "  FALLA  HSTS ausente"; fail=1; }
printf '%s' "$hdr" | grep -i "x-robots-tag" | grep -iq noindex && echo "  OK     /admin noindex" || { echo "  FALLA  /admin sin noindex"; fail=1; }

root="$(curl -s -o /dev/null -w '%{http_code}' "$SITE/")"
admin="$(curl -sL -o /dev/null -w '%{http_code}' "$SITE/admin")"
[ "$root" = "200" ]  && echo "  OK     / → 200"      || { echo "  FALLA  / → $root"; fail=1; }
[ "$admin" = "200" ] && echo "  OK     /admin → 200" || { echo "  FALLA  /admin → $admin"; fail=1; }

echo
if [ "$fail" = "0" ]; then
  echo "RESULTADO: TODO OK ✅"
else
  echo "RESULTADO: ⚠️ SE DETECTÓ AL MENOS UNA REGRESIÓN — revisa las líneas 'FALLA' de arriba."
  echo "Si la falla es de RLS: revisa cambios recientes en la consola de Supabase y corre en el SQL Editor:"
  echo "  SELECT tablename, policyname, roles, cmd FROM pg_policies"
  echo "  WHERE schemaname='public' AND (qual='true' OR '{public}'::name[] && roles::name[]) ORDER BY tablename;"
fi
exit "$fail"
