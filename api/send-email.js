import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';

const resend = new Resend(process.env.RESEND_API_KEY);

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://alphadrivers.mx');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).end();

  // Solo admins/concierge/staff autenticados pueden enviar correos
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No autorizado' });
  }
  const token = authHeader.split(' ')[1];
  const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token);
  if (authErr || !user) return res.status(401).json({ error: 'Sesión inválida' });

  const callerRole = user.app_metadata?.role || user.user_metadata?.role;
  if (!['admin', 'concierge', 'staff'].includes(callerRole)) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }

  const { to, subject, html } = req.body;
  if (!to || !subject || !html) {
    return res.status(400).json({ error: 'Missing required fields: to, subject, html' });
  }

  const { data, error } = await resend.emails.send({
    from: 'ALPHA DRIVERS <noreply@alphadrivers.mx>',
    to,
    subject,
    html,
  });

  if (error) return res.status(400).json({ error });
  return res.status(200).json({ data });
}
