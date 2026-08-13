import { createClient } from '@supabase/supabase-js';
import { initSentry, captureException } from './_sentry.js';
import { rateLimit } from './_ratelimit.js';
initSentry();

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const ALLOWED_ORIGINS = ['https://www.alphadrivers.mx', 'https://alphadrivers.mx'];

export default async function handler(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGINS.includes(origin) ? origin : 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const ip = (req.headers['x-vercel-forwarded-for'] || req.headers['x-real-ip'] || req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown').split(',')[0].trim();
  if (!(await rateLimit(supabaseAdmin, 'validate-invite:' + ip, 5, 15 * 60))) {
    return res.status(429).json({ valid: false, error: 'Demasiados intentos. Intenta en 15 minutos.' });
  }

  const { code } = req.body;
  if (!code || typeof code !== 'string' || !/^[A-Z0-9\-]{3,24}$/.test(code.trim().toUpperCase())) {
    return res.status(400).json({ valid: false, error: 'Código inválido' });
  }

  const { data, error } = await supabaseAdmin
    .from('invite_codes')
    .select('id, used')
    .eq('code', code.trim().toUpperCase())
    .eq('used', false)
    .maybeSingle();

  if (error) { captureException(new Error(error.message), { endpoint: 'validate-invite' }); }
  if (error || !data) {
    return res.status(200).json({ valid: false });
  }

  return res.status(200).json({ valid: true, invite_id: data.id });
}
