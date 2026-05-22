// api/create-auth-user.js
// Vercel serverless function — crea usuario en Supabase Auth con contraseña hasheada
// Solo accesible para admins con sesión válida de Supabase

import { createClient } from '@supabase/supabase-js';

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const ALLOWED_ORIGINS = ['https://alphadrivers.mx'];
export default async function handler(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGINS.includes(origin) ? origin : 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Verificar que el llamador es un admin autenticado
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No autorizado' });
  }
  const token = authHeader.split(' ')[1];

  // Validar el JWT con Supabase
  const { data: { user: caller }, error: authErr } = await supabaseAdmin.auth.getUser(token);
  if (authErr || !caller) return res.status(401).json({ error: 'Sesión inválida' });

  // app_metadata solo escribible por service role — NO user_metadata como fallback
  const callerRole = caller.app_metadata?.role;
  if (!['admin', 'concierge', 'staff'].includes(callerRole)) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }

  const { action, email, password, member_id, role } = req.body;

  // ── ACCIÓN: actualizar contraseña de usuario existente ────────
  if (action === 'update-password') {
    if (callerRole !== 'admin') return res.status(403).json({ error: 'Solo admins pueden cambiar contraseñas de staff' });
    if (!email || !password) return res.status(400).json({ error: 'email y password son requeridos' });
    if (password.length < 8) return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });

    const authEmail = email.includes('@') ? email.toLowerCase().trim() : `${email.toLowerCase().trim()}@alphadrivers.mx`;

    // Buscar usuario por email
    let targetId = null;
    let page = 1;
    while (true) {
      const { data: batch } = await supabaseAdmin.auth.admin.listUsers({ page, perPage: 1000 });
      const found = batch?.users?.find(u => u.email === authEmail);
      if (found) { targetId = found.id; break; }
      if (!batch?.users?.length || batch.users.length < 1000) break;
      page++;
    }
    if (!targetId) return res.status(404).json({ error: 'Usuario no encontrado' });

    const { error: upErr } = await supabaseAdmin.auth.admin.updateUserById(targetId, { password });
    if (upErr) { console.error('updateUserById error:', upErr.message); return res.status(400).json({ error: 'No se pudo actualizar la contraseña' }); }
    return res.status(200).json({ updated: true });
  }

  // ── ACCIÓN: crear nuevo usuario ───────────────────────────────
  if (!email || !password) return res.status(400).json({ error: 'email y password son requeridos' });
  if (password.length < 8) return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });

  // Solo admins pueden crear roles privilegiados
  const allowedRoles = callerRole === 'admin' ? ['member','admin','concierge','staff'] : ['member'];
  const safeRole = allowedRoles.includes(role) ? role : 'member';

  // Construir email de auth: si ya tiene @, usarlo directo; si no, agregar @alphadrivers.mx
  const authEmail = email.includes('@') ? email.toLowerCase().trim() : `${email.toLowerCase().trim()}@alphadrivers.mx`;

  const { must_change_password } = req.body;

  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: authEmail,
    password,
    email_confirm: true,
    user_metadata: {
      role: safeRole,
      member_id: member_id || null,
      display_name: email.split('@')[0],
      ...(must_change_password ? { must_change_password: true } : {}),
    },
  });

  if (error) {
    if (error.message?.includes('already registered')) {
      const { data: existing } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const found = existing?.users?.find(u => u.email === authEmail);
      if (found) return res.status(200).json({ user_id: found.id, existed: true });
    }
    console.error('createUser error:', error.message);
    return res.status(400).json({ error: 'No se pudo crear el usuario' });
  }

  // Setear app_metadata (solo escribible por service role)
  await supabaseAdmin.auth.admin.updateUserById(data.user.id, {
    app_metadata: { role: safeRole, member_id: member_id || null }
  });

  return res.status(200).json({ user_id: data.user.id, existed: false });
}
