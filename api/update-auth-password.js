// api/update-auth-password.js
// Vercel serverless function — actualiza contraseña de un usuario existente en Supabase Auth
// Solo accesible para admins autenticados (verifica app_metadata.role, no user_metadata)

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

  const { data: { user: caller }, error: authErr } = await supabaseAdmin.auth.getUser(token);
  if (authErr || !caller) return res.status(401).json({ error: 'Sesión inválida' });

  // app_metadata solo escribible por service role — no user_metadata (usuario puede escribirla)
  const callerRole = caller.app_metadata?.role;
  if (callerRole !== 'admin') {
    return res.status(403).json({ error: 'Solo admins pueden actualizar contraseñas' });
  }

  const { user_id, password, email } = req.body;
  if (!password) return res.status(400).json({ error: 'password es requerido' });
  if (password.length < 8) return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });

  // Permitir buscar por user_id o por email
  let targetUserId = user_id;
  if (!targetUserId && email) {
    const authEmail = email.includes('@') ? email.toLowerCase() : `${email.toLowerCase()}@alphadrivers.mx`;
    // Paginar para manejar más de 1000 usuarios
    let page = 1;
    while (true) {
      const { data: batch } = await supabaseAdmin.auth.admin.listUsers({ page, perPage: 1000 });
      const found = batch?.users?.find(u => u.email === authEmail);
      if (found) { targetUserId = found.id; break; }
      if (!batch?.users?.length || batch.users.length < 1000) break;
      page++;
    }
    if (!targetUserId) return res.status(404).json({ error: 'Usuario no encontrado' });
  }

  if (!targetUserId) return res.status(400).json({ error: 'user_id o email son requeridos' });

  const { error } = await supabaseAdmin.auth.admin.updateUserById(targetUserId, { password });
  if (error) return res.status(400).json({ error: error.message });

  return res.status(200).json({ success: true });
}
