// Shared rate limiter backed by the Supabase `rate_limits` table + check_rate_limit RPC.
// Works across all serverless instances (unlike a per-instance in-memory Map).
// Falls back to a per-instance counter if the RPC is unavailable, so a DB
// hiccup degrades the limit instead of failing fully open.

const _mem = new Map();

function memCheck(key, max, windowSeconds) {
  const now = Date.now();
  const windowMs = windowSeconds * 1000;
  const entry = _mem.get(key) || { count: 0, reset: now + windowMs };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + windowMs; }
  entry.count++;
  _mem.set(key, entry);
  if (_mem.size > 1000) { for (const [k, v] of _mem) { if (v.reset < now) _mem.delete(k); } }
  return entry.count <= max;
}

// Returns true if the caller is still under the limit, false if it should be blocked.
export async function rateLimit(supabaseAdmin, key, max, windowSeconds) {
  try {
    const { data, error } = await supabaseAdmin.rpc('check_rate_limit', {
      p_key: key,
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    if (error) throw error;
    return data === true;
  } catch (_e) {
    // RPC missing / DB unreachable — degrade to per-instance limiting.
    return memCheck(key, max, windowSeconds);
  }
}
