// api/send-invite.js
// Endpoint autenticado para que miembros envíen correos de invitación.
// El miembro envía invite_code_id; la plantilla y los datos se construyen server-side.
// No es relay abierto: el HTML nunca viene del cliente.

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
  const ALLOWED_ORIGINS = ['https://alphadrivers.mx'];
  const origin = req.headers.origin || '';
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGINS.includes(origin) ? origin : 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Verificar JWT del miembro
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No autorizado' });
  }
  const token = authHeader.split(' ')[1];
  const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token);
  if (authErr || !user) return res.status(401).json({ error: 'Sesión inválida' });

  // Solo miembros (y admin/staff) pueden usar este endpoint
  const callerRole = user.app_metadata?.role;
  if (!['member', 'admin', 'concierge', 'staff'].includes(callerRole)) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }

  const { invite_code_id } = req.body;
  if (!invite_code_id || typeof invite_code_id !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(invite_code_id)) {
    return res.status(400).json({ error: 'invite_code_id inválido' });
  }

  // Leer el código de invitación desde la DB (datos no vienen del cliente)
  const { data: invite, error: dbErr } = await supabaseAdmin
    .from('invite_codes')
    .select('id, code, referred_name, referred_email, referred_by, created_at, used')
    .eq('id', invite_code_id)
    .single();

  if (dbErr || !invite) return res.status(404).json({ error: 'Código de invitación no encontrado' });
  if (invite.used) return res.status(400).json({ error: 'Este código ya fue usado' });

  // Validar que el miembro que llama es el dueño del código (previene que un miembro envíe invitaciones de otro)
  const callerId = user.app_metadata?.member_id;
  if (callerRole === 'member' && callerId && invite.referred_by !== callerId) {
    return res.status(403).json({ error: 'No tienes permiso para enviar esta invitación' });
  }

  // Validar que el código fue creado hace menos de 24 horas (evita reenvíos masivos de códigos viejos)
  const ageHours = (Date.now() - new Date(invite.created_at).getTime()) / (1000 * 60 * 60);
  if (ageHours > 24) {
    return res.status(400).json({ error: 'El código es demasiado antiguo para reenviar la invitación' });
  }

  if (!invite.referred_email) return res.status(400).json({ error: 'El código no tiene email destinatario' });

  // Leer nombre del miembro que invita desde la tabla members
  let memberName = 'Un miembro Alpha Drivers';
  if (invite.referred_by) {
    const { data: memberRow } = await supabaseAdmin
      .from('members')
      .select('name')
      .eq('id', invite.referred_by)
      .single();
    if (memberRow?.name) memberName = memberRow.name;
  }

  // Construir template server-side — todo escapado
  const safeName       = escHtml(invite.referred_name || '');
  const safeEmail      = escHtml(invite.referred_email);
  const safeCode       = escHtml(invite.code);
  const safeMemberName = escHtml(memberName);
  const logoUrl        = 'https://alphadrivers.mx/imagenes/logo-ad.png';

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:0;background:#0a0a0a;font-family:Arial,sans-serif;color:#fff"><table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:48px 16px"><table width="100%" style="max-width:520px"><tr><td style="padding-bottom:36px;border-bottom:1px solid #1e1e1e;text-align:center"><img src="${logoUrl}" alt="ALPHA DRIVERS" style="height:44px;display:inline-block"/></td></tr><tr><td style="padding:40px 0 24px"><p style="font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:#555;margin:0 0 20px">Invitación Exclusiva</p><h1 style="font-size:22px;font-weight:700;margin:0 0 16px;line-height:1.3">Hola, ${safeName || 'amigo'}.</h1><p style="font-size:14px;color:#aaa;line-height:1.9;margin:0 0 8px"><strong style="color:#fff">${safeMemberName}</strong> te ha seleccionado personalmente para unirte a <strong style="color:#fff">ALPHA DRIVERS</strong>, el club privado de membresía para pilotos y entusiastas de la conducción de alto desempeño.</p></td></tr><tr><td style="padding:32px 0;text-align:center;border-top:1px solid #1a1a1a;border-bottom:1px solid #1a1a1a"><p style="font-size:10px;letter-spacing:.25em;text-transform:uppercase;color:#555;margin:0 0 16px">Tu código de invitación</p><div style="display:inline-block;background:#fff;color:#000;font-family:monospace;font-size:26px;font-weight:700;letter-spacing:.25em;padding:16px 36px">${safeCode}</div><p style="font-size:11px;color:#555;margin:20px 0 0;line-height:1.7">Ingresa a <strong style="color:#aaa">alphadrivers.mx</strong> y usa este código<br>al completar tu solicitud de membresía.</p></td></tr><tr><td style="padding:28px 0;text-align:center"><a href="https://alphadrivers.mx" style="display:inline-block;background:#fff;color:#000;font-size:10px;font-weight:700;letter-spacing:.25em;text-transform:uppercase;text-decoration:none;padding:14px 36px">Solicitar Membresía</a></td></tr><tr><td style="padding:36px 0 0;text-align:center"><p style="font-size:10px;color:#333;line-height:1.8;margin:0">ALPHA DRIVERS · Club Privado de Membresía Deportiva<br>alphadrivers.mx · Por favor no respondas a este correo.</p></td></tr></table></td></tr></table></body></html>`;

  const { error: mailErr } = await resend.emails.send({
    from: 'ALPHA DRIVERS <noreply@alphadrivers.mx>',
    to: invite.referred_email,
    subject: `${memberName} te ha invitado a ALPHA DRIVERS`,
    html,
  });

  if (mailErr) return res.status(400).json({ error: 'Error enviando correo' });
  return res.status(200).json({ sent: true });
}
