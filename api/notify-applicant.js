// api/notify-applicant.js
// Endpoint público (sin JWT) para enviar el correo de confirmación al aplicante.
// No es un relay abierto: la plantilla es fija (server-side) y los datos
// vienen de la DB, no del cliente. El cliente solo envía el application_id.
// La solicitud debe existir en la tabla `applications` y tener menos de 10 min de antigüedad.

import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';

const resend = new Resend(process.env.RESEND_API_KEY);

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

function escHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export default async function handler(req, res) {
  const _ao = ['https://alphadrivers.mx'];
  const _or = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', _ao.includes(_or) ? _or : 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { application_id } = req.body;
  if (!application_id || typeof application_id !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(application_id)) {
    return res.status(400).json({ error: 'application_id inválido' });
  }

  // Leer la aplicación desde la DB (datos vienen del servidor, no del cliente)
  const { data: app, error: dbErr } = await supabaseAdmin
    .from('applications')
    .select('id, name, email, city, created_at')
    .eq('id', application_id)
    .single();

  if (dbErr || !app) return res.status(404).json({ error: 'Solicitud no encontrada' });

  // Validar que la solicitud fue creada hace menos de 10 minutos (evita reenvíos maliciosos)
  const ageMs = Date.now() - new Date(app.created_at).getTime();
  if (ageMs > 10 * 60 * 1000) {
    return res.status(400).json({ error: 'La solicitud es demasiado antigua para reenviar confirmación' });
  }

  if (!app.email) return res.status(400).json({ error: 'La solicitud no tiene email' });

  const name     = escHtml(app.name || '');
  const firstName = escHtml((app.name || '').split(' ')[0] || '');
  const email    = escHtml(app.email || '');
  const city     = escHtml(app.city || '—');
  const logoUrl  = 'https://alphadrivers.mx/imagenes/logo-ad.png';

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:0;background:#0a0a0a;font-family:Arial,sans-serif;color:#fff"><table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:48px 16px"><table width="100%" style="max-width:520px"><tr><td style="padding-bottom:36px;border-bottom:1px solid #1e1e1e;text-align:center"><img src="${logoUrl}" alt="ALPHA DRIVERS" style="height:44px;display:inline-block"/></td></tr><tr><td style="padding:40px 0 24px"><p style="font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:#555;margin:0 0 20px">Confirmación de Solicitud</p><h1 style="font-size:22px;font-weight:700;margin:0 0 20px;line-height:1.4">Hola, ${firstName}.</h1><p style="font-size:14px;color:#aaa;line-height:1.9;margin:0">Hemos recibido tu solicitud de membresía en <strong style="color:#fff">ALPHA DRIVERS</strong>. Nuestro equipo la está revisando cuidadosamente y nos pondremos en contacto contigo pronto con una respuesta.</p></td></tr><tr><td style="padding:28px 0;border-top:1px solid #1a1a1a;border-bottom:1px solid #1a1a1a"><table width="100%"><tr><td style="padding:8px 0"><span style="font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:#444">Nombre</span><br><span style="font-size:13px;color:#ddd">${name}</span></td></tr><tr><td style="padding:8px 0"><span style="font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:#444">Email</span><br><span style="font-size:13px;color:#ddd">${email}</span></td></tr><tr><td style="padding:8px 0"><span style="font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:#444">Ciudad</span><br><span style="font-size:13px;color:#ddd">${city}</span></td></tr></table></td></tr><tr><td style="padding:36px 0 0;text-align:center"><p style="font-size:10px;color:#333;line-height:1.8;margin:0">ALPHA DRIVERS · Club Privado de Membresía Deportiva<br>alphadrivers.mx · Por favor no respondas a este correo.</p></td></tr></table></td></tr></table></body></html>`;

  const { error: mailErr } = await resend.emails.send({
    from: 'ALPHA DRIVERS <noreply@alphadrivers.mx>',
    to: app.email,
    subject: 'ALPHA DRIVERS — Solicitud recibida',
    html,
  });

  if (mailErr) return res.status(400).json({ error: mailErr.message || 'Error enviando correo' });
  return res.status(200).json({ sent: true });
}
