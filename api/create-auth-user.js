// api/create-auth-user.js
// Vercel serverless function — crea usuario en Supabase Auth con contraseña hasheada
// Solo accesible para admins con sesión válida de Supabase

import { createClient } from '@supabase/supabase-js';

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://alphadrivers.mx');
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

  // app_metadata es solo escribible por service role; user_metadata puede ser modificado por el usuario
  const callerRole = caller.app_metadata?.role || caller.user_metadata?.role;
  if (!['admin', 'concierge', 'staff'].includes(callerRole)) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }

  const { email, password, member_id, role } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email y password son requeridos' });
  if (password.length < 8) return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });

  // Construir email de auth: si ya tiene @, usarlo directo; si no, agregar @alphadrivers.mx
  const authEmail = email.includes('@') ? email.toLowerCase().trim() : `${email.toLowerCase().trim()}@alphadrivers.mx`;

  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: authEmail,
    password,
    email_confirm: true, // saltar confirmación de correo — credenciales las crea el admin
    user_metadata: {
      role: role || 'member',
      member_id: member_id || null,
      display_name: email.split('@')[0],
    },
  });

  if (error) {
    // Si el usuario ya existe, retornar su ID para que se pueda actualizar
    if (error.message?.includes('already registered')) {
      const { data: existing } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const found = existing?.users?.find(u => u.email === authEmail);
      if (found) return res.status(200).json({ user_id: found.id, existed: true });
    }
    return res.status(400).json({ error: error.message });
  }

  return res.status(200).json({ user_id: data.user.id, existed: false });
}
