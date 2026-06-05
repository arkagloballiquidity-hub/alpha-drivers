import { createClient } from '@supabase/supabase-js';

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

// Rate limiting — 5 intentos por IP cada 15 minutos
const _rl = new Map();
function checkRateLimit(ip) {
  const now = Date.now();
  const window = 15 * 60 * 1000;
  const max = 5;
  const entry = _rl.get(ip) || { count: 0, reset: now + window };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + window; }
  entry.count++;
  _rl.set(ip, entry);
  if (_rl.size > 500) {
    const old = now - window;
    for (const [k, v] of _rl) { if (v.reset < old) _rl.delete(k); }
  }
  return entry.count <= max;
}

const ALLOWED_ORIGINS = ['https://alphadrivers.mx'];

export default async function handler(req, res) {
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGINS.includes(origin) ? origin : 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const ip = (req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown').split(',')[0].trim();
  if (!checkRateLimit(ip)) {
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

  if (error || !data) {
    return res.status(200).json({ valid: false });
  }

  return res.status(200).json({ valid: true, invite_id: data.id });
}
