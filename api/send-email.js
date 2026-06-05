import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';
import { initSentry, captureException } from './_sentry.js';
initSentry();

// Rate limiting en memoria — 20 emails por usuario autenticado por hora
const _rl = new Map();
function checkRateLimit(userId) {
  const now = Date.now();
  const window = 60 * 60 * 1000;
  const max = 20;
  const entry = _rl.get(userId) || { count: 0, reset: now + window };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + window; }
  entry.count++;
  _rl.set(userId, entry);
  return entry.count <= max;
}

const resend = new Resend(process.env.RESEND_API_KEY);

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
  if (req.method !== 'POST') return res.status(405).end();

  // Solo admins/concierge/staff autenticados pueden enviar correos
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No autorizado' });
  }
  const token = authHeader.split(' ')[1];
  const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token);
  if (authErr || !user) return res.status(401).json({ error: 'Sesión inválida' });

  const callerRole = user.app_metadata?.role;
  if (!['admin', 'concierge', 'staff'].includes(callerRole)) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }

  // Rate limit por usuario — 20 emails/hora
  if (!checkRateLimit(user.id)) {
    return res.status(429).json({ error: 'Límite de envíos alcanzado. Intenta en una hora.' });
  }

  const { to, subject, html } = req.body;
  if (!to || !subject || !html) {
    return res.status(400).json({ error: 'Missing required fields: to, subject, html' });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(to))) {
    return res.status(400).json({ error: 'Dirección de correo inválida' });
  }

  const { data, error } = await resend.emails.send({
    from: 'ALPHA DRIVERS <noreply@alphadrivers.mx>',
    to,
    subject,
    html,
  });

  if (error) { captureException(new Error(error.message || 'Resend error'), { to, subject }); return res.status(400).json({ error: 'Error al enviar correo' }); }
  return res.status(200).json({ data });
}
