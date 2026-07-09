// SimpleDictation license API — Cloudflare Worker (ES modules), D1-backed.
// Account: API KING. No external API dependency (no Lemon Squeezy). D1 is the truth.
// Zero npm deps: WebCrypto + native fetch only. Crockford base32 inlined (must match
// scripts/gen-keys.mjs AND Sources/Base32.swift byte-for-byte, INCLUDING rejecting U).
//
// Public endpoints (macOS app + optionally the site):
//   POST /v1/activate   { code, device_id, device_name?, email? }
//        -> { token, tier, email, activations, max_activations }
//   POST /v1/validate   { token }   -> { valid, verified, claim? }   (informational; see note)
//
// Admin endpoints (Authorization: Bearer <ADMIN_TOKEN>):
//   GET   /admin/keys?status=&batch=&q=&page=&per_page=
//   GET   /admin/stats
//   POST  /admin/keys/generate   { n, batch?, tier?, max_activations? }
//   POST  /admin/keys/:id/revoke
//   POST  /admin/keys/:id/unrevoke
//   GET   /admin/export.csv?status=&batch=
//
// Secrets (wrangler secret put):
//   ED25519_PRIVATE_KEY_B64  base32 of the 48-byte PKCS8 DER (exactly what gen-keys.mjs prints)
//   ADMIN_TOKEN              long random string
//   IP_SALT                  random, for hashing IPs
//   PUBLIC_KEY               (OPTIONAL) base32 raw 32-byte public key — ONLY to make
//                            /v1/validate actually verify signatures. See loud note there.

// ---------- Crockford base32 (MUST match gen-keys.mjs + Sources/Base32.swift) ----------
// Alphabet excludes I L O U. Decode folds I/L->1 and O->0. U IS REJECTED (Crockford):
// Base32.swift rejects U, so folding U->anything here would decode a token to bytes the
// app rejects -> silent verify failure. Do not "tolerate" U.
const B32_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const B32_LOOKUP = (() => {
  const m = {};
  for (let i = 0; i < B32_ALPHABET.length; i++) m[B32_ALPHABET[i]] = i;
  m['I'] = m['L'] = 1; m['O'] = 0;   // fold look-alikes; U intentionally absent (rejected)
  return m;
})();

function base32Encode(bytes) {
  let bits = 0, value = 0, out = '';
  for (let i = 0; i < bytes.length; i++) {
    value = (value << 8) | bytes[i]; bits += 8;
    while (bits >= 5) { out += B32_ALPHABET[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32_ALPHABET[(value << (5 - bits)) & 31];
  return out; // no padding, uppercase
}

function base32Decode(str) {
  const s = str.toUpperCase().replace(/[^0-9A-Z]/g, '');
  let bits = 0, value = 0; const out = [];
  for (let i = 0; i < s.length; i++) {
    const c = B32_LOOKUP[s[i]];
    if (c === undefined) throw new Error('bad base32 char'); // U and any stray char -> reject
    value = (value << 5) | c; bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return new Uint8Array(out);
}

// ---------- helpers ----------
const enc = new TextEncoder();
const dec = new TextDecoder();

function nowISO() { return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'); }

async function sha256Hex(str) {
  const buf = await crypto.subtle.digest('SHA-256', enc.encode(str));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Canonical form — IDENTICAL to gen-keys.mjs canonicalizeCode(): uppercase, fold
// I/L->1 and O->0, strip everything non-alphanumeric. NOTE: the SD42 prefix is KEPT
// (not stripped), matching gen-keys, so code_canon = "SD42R2RDZGDPAWAZ" (16 chars).
function canonicalizeCode(raw) {
  const s = String(raw || '').toUpperCase()
    .replace(/[IL]/g, '1').replace(/O/g, '0').replace(/[^0-9A-Z]/g, '');
  if (s.length !== 16) return null; // SD42 (4) + 12 body chars
  return s;
}

// ---------- CORS ----------
function corsHeaders(req, env) {
  const origin = req.headers.get('Origin') || '';
  const allowed = (env.ALLOWED_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean);
  const ok = allowed.includes(origin);
  return {
    'Access-Control-Allow-Origin': ok ? origin : (allowed[0] || 'https://cfranci.github.io'),
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}
// Build a JSON response WITH cors baked in (no re-wrapping of consumed Response bodies).
function json(data, status, cors, extra = {}) {
  return new Response(JSON.stringify(data), {
    status, headers: { 'Content-Type': 'application/json', ...cors, ...extra },
  });
}

// ---------- rate limiting (fixed-window, D1-backed, free tier) ----------
async function rateLimit(env, key, perMin) {
  const windowStart = Math.floor(Date.now() / 60000);
  const bucket = `${key}:${windowStart}`;
  const expires = (windowStart + 1) * 60;
  await env.DB.prepare(
    `INSERT INTO rate_limits (bucket, hits, expires_at) VALUES (?, 1, ?)
     ON CONFLICT(bucket) DO UPDATE SET hits = hits + 1`
  ).bind(bucket, expires).run();
  const row = await env.DB.prepare(`SELECT hits FROM rate_limits WHERE bucket = ?`).bind(bucket).first();
  await env.DB.prepare(`DELETE FROM rate_limits WHERE expires_at < ?`).bind(windowStart * 60).run(); // opportunistic sweep
  return (row?.hits ?? 1) <= perMin;
}

// ---------- Ed25519 signing (WebCrypto, no JWT libs) ----------
// ED25519_PRIVATE_KEY_B64 = base32 of the full 48-byte PKCS8 DER (what gen-keys.mjs prints).
// Import directly as 'pkcs8' — NO runtime seed-wrapping. ('raw' import of a private key is
// invalid for ['sign']; gen-keys verified this live.)
let _signingKeyPromise = null;
function getSigningKey(env) {
  if (!_signingKeyPromise) {
    const pkcs8 = base32Decode(env.ED25519_PRIVATE_KEY_B64);
    if (pkcs8.length !== 48) throw new Error('ED25519_PRIVATE_KEY_B64 must decode to a 48-byte PKCS8 DER');
    _signingKeyPromise = crypto.subtle.importKey('pkcs8', pkcs8, { name: 'Ed25519' }, false, ['sign']);
  }
  return _signingKeyPromise;
}

// Mint the SD1- token. Payload is the DOC'S EXACT Claim { v, kid, sku, email, order, iid }
// in THIS fixed insertion order (must byte-match gen-keys.mjs:209-216 and Swift's Claim).
// For self-issued keys, order === iid === the pretty code. Signed over the exact serialized
// bytes, never re-serialized. NO iat/exp (the doc's Claim has neither).
async function mintToken(env, { code, email }) {
  const payload = JSON.stringify({
    v: 1,
    kid: env.KID,
    sku: env.SKU,
    email: email || '',
    order: code,   // self-issued: short code stands in for LS order_id
    iid: code,     // self-issued: short code stands in for LS instance.id
  });
  const payloadBytes = enc.encode(payload);
  const key = await getSigningKey(env);
  const sig = new Uint8Array(await crypto.subtle.sign('Ed25519', key, payloadBytes));
  return `SD1-${base32Encode(payloadBytes)}.${base32Encode(sig)}`;
}

// ---------- server-side key generation (for /admin/keys/generate) ----------
// Mirrors gen-keys.mjs makeCode(): SD42- + 12 Crockford body chars from CSPRNG.
function randomCode() {
  const rnd = crypto.getRandomValues(new Uint8Array(8)); // 64 bits, CSPRNG (never Math.random)
  const body = base32Encode(rnd).slice(0, 12).padEnd(12, '0');
  return `SD42-${body.slice(0, 4)}-${body.slice(4, 8)}-${body.slice(8, 12)}`;
}
function randomId() {
  return [...crypto.getRandomValues(new Uint8Array(8))]  // 16 hex chars, matches gen-keys randomBytes(8)
    .map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function logActivation(env, { license_id, codeCanon, deviceId, deviceName, email, ipHash, outcome }) {
  try {
    await env.DB.prepare(
      `INSERT INTO activations (license_id, code_canon, device_id, device_name, email, ip_hash, outcome)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(license_id, codeCanon, deviceId, deviceName || null, email || null, ipHash, outcome).run();
  } catch (_) { /* logging must never break activation */ }
}

// ---------- public: activate ----------
async function handleActivate(req, env, cors) {
  let body;
  try { body = await req.json(); } catch { return json({ error: 'bad_json' }, 400, cors); }
  const codeCanon = canonicalizeCode(body.code);
  const deviceId = String(body.device_id || '').trim().slice(0, 128);
  const deviceName = body.device_name ? String(body.device_name).slice(0, 128) : null;
  const email = body.email ? String(body.email).trim().slice(0, 256) : null;

  const ipHash = await sha256Hex((req.headers.get('CF-Connecting-IP') || '') + (env.IP_SALT || ''));

  // Rate limit per IP. FAIL OPEN on limiter DB hiccups (a limiter bug must never block a legit user).
  try {
    const ok = await rateLimit(env, `activate:${ipHash}`, parseInt(env.RATE_LIMIT_PER_MIN || '8', 10));
    if (!ok) return json({ error: 'rate_limited', message: 'Too many attempts, wait a minute.' }, 429, cors);
  } catch (_) { /* ignore */ }

  if (!codeCanon) return json({ error: 'bad_code', message: 'That does not look like a SimpleDictation key.' }, 400, cors);
  if (!deviceId)  return json({ error: 'missing_device', message: 'Missing device id.' }, 400, cors);

  const lic = await env.DB.prepare(`SELECT * FROM licenses WHERE code_canon = ?`).bind(codeCanon).first();

  if (!lic) {
    await logActivation(env, { license_id: null, codeCanon, deviceId, deviceName, email, ipHash, outcome: 'rejected_unknown' });
    return json({ error: 'unknown_key', message: 'Key not found. Check for typos.' }, 404, cors);
  }
  if (lic.status === 'revoked') {
    await logActivation(env, { license_id: lic.id, codeCanon, deviceId, deviceName, email, ipHash, outcome: 'rejected_revoked' });
    return json({ error: 'revoked', message: 'This key was revoked. Contact support.' }, 403, cors);
  }

  let devices = [];
  try { devices = JSON.parse(lic.device_ids || '[]'); } catch { devices = []; }
  const alreadyThisDevice = devices.includes(deviceId);

  if (!alreadyThisDevice && lic.activation_count >= lic.max_activations) {
    await logActivation(env, { license_id: lic.id, codeCanon, deviceId, deviceName, email, ipHash, outcome: 'rejected_cap' });
    return json({
      error: 'activation_limit',
      message: `This key is already used on ${lic.max_activations} device(s).`,
    }, 409, cors);
  }

  // Token binds to the PRETTY code (order === iid === lic.code), matching gen-keys self-issued keys.
  const token = await mintToken(env, { code: lic.code, email: email || lic.email });

  if (!alreadyThisDevice) {
    devices.push(deviceId);
    await env.DB.prepare(
      `UPDATE licenses
         SET status='active', activation_count=?, device_ids=?,
             email=COALESCE(?, email), activated_at=COALESCE(activated_at, ?)
       WHERE id=?`
    ).bind(devices.length, JSON.stringify(devices), email, nowISO(), lic.id).run();
    await logActivation(env, { license_id: lic.id, codeCanon, deviceId, deviceName, email, ipHash, outcome: 'activated' });
  } else {
    // Idempotent: same device, fresh token, NO seat burned.
    await logActivation(env, { license_id: lic.id, codeCanon, deviceId, deviceName, email, ipHash, outcome: 'reactivated' });
  }

  return json({
    token,
    tier: lic.tier,
    email: email || lic.email || '',
    activations: alreadyThisDevice ? lic.activation_count : devices.length,
    max_activations: lic.max_activations,
  }, 200, cors);
}

// ---------- public: validate (INFORMATIONAL ONLY) ----------
// LOUD NOTE: the macOS app verifies Ed25519 OFFLINE with its embedded public key — that is
// the real trust boundary (doc §3). This endpoint is support/debug convenience. It only
// cryptographically VERIFIES a token if the OPTIONAL PUBLIC_KEY secret is set (a Worker
// holding only the private signing key cannot derive the public key in sign-only mode).
// When PUBLIC_KEY is absent it DEGRADES to a signature-agnostic decode + a D1 revocation
// check and returns { valid, verified:false } so callers KNOW the signature was not checked.
// NEVER treat this endpoint as an authorization oracle.
let _pubKeyPromise = null;
function getPublicKey(env) {
  if (!_pubKeyPromise) {
    _pubKeyPromise = env.PUBLIC_KEY
      ? crypto.subtle.importKey('raw', base32Decode(env.PUBLIC_KEY), { name: 'Ed25519' }, false, ['verify'])
      : Promise.reject(new Error('no PUBLIC_KEY var'));
  }
  return _pubKeyPromise;
}
async function handleValidate(req, env, cors) {
  let body;
  try { body = await req.json(); } catch { return json({ error: 'bad_json' }, 400, cors); }
  const token = String(body.token || '');
  if (!token.startsWith('SD1-')) return json({ valid: false }, 200, cors);
  try {
    const [p, s] = token.slice(4).split('.');
    const payload = base32Decode(p);
    const claim = JSON.parse(dec.decode(payload));  // { v, kid, sku, email, order, iid }
    // D1 revocation cross-check (cheap, always available): self-issued -> order === iid === code.
    if (claim.order) {
      const canon = canonicalizeCode(claim.order);
      if (canon) {
        const row = await env.DB.prepare(`SELECT status FROM licenses WHERE code_canon = ?`).bind(canon).first();
        if (row && row.status === 'revoked') return json({ valid: false, verified: false, reason: 'revoked' }, 200, cors);
      }
    }
    // Signature verification only if PUBLIC_KEY is configured.
    let verified = false;
    try {
      const pub = await getPublicKey(env);
      verified = await crypto.subtle.verify('Ed25519', pub, base32Decode(s), payload);
      if (!verified) return json({ valid: false, verified: false }, 200, cors);
    } catch (_) { /* no PUBLIC_KEY -> informational only */ }
    return json({ valid: true, verified, claim }, 200, cors);
  } catch { return json({ valid: false }, 200, cors); }
}

// ---------- admin auth (constant-time) ----------
function requireAdmin(req, env) {
  const auth = req.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const a = enc.encode(token), b = enc.encode(env.ADMIN_TOKEN || '');
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0 && a.length > 0;
}

// ---------- admin: list (paginated) ----------
async function handleAdminList(env, url, cors) {
  const status = url.searchParams.get('status');
  const batch = url.searchParams.get('batch');
  const q = url.searchParams.get('q');
  const perPage = Math.min(Math.max(parseInt(url.searchParams.get('per_page') || '100', 10), 1), 1000);
  const page = Math.max(parseInt(url.searchParams.get('page') || '1', 10), 1);
  const offset = (page - 1) * perPage;

  const where = [], binds = [];
  if (status && status !== 'all') { where.push('status = ?'); binds.push(status); }
  if (batch && batch !== 'all')   { where.push('batch = ?');  binds.push(batch); }
  if (q) { where.push('(code LIKE ? OR email LIKE ? OR note LIKE ?)'); binds.push(`%${q}%`, `%${q}%`, `%${q}%`); }
  const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const countRow = await env.DB.prepare(`SELECT COUNT(*) AS n FROM licenses ${clause}`).bind(...binds).first();
  const rows = await env.DB.prepare(
    `SELECT id, code, status, batch, tier, email, max_activations, activation_count,
            device_ids, note, activated_at, created_at
       FROM licenses ${clause}
      ORDER BY created_at ASC, code ASC
      LIMIT ? OFFSET ?`
  ).bind(...binds, perPage, offset).all();

  const counts = await env.DB.prepare(
    `SELECT COUNT(*) AS total,
            SUM(CASE WHEN status='unused'  THEN 1 ELSE 0 END) AS unused,
            SUM(CASE WHEN status='active'  THEN 1 ELSE 0 END) AS active,
            SUM(CASE WHEN status='revoked' THEN 1 ELSE 0 END) AS revoked
       FROM licenses ${clause}`
  ).bind(...binds).first();

  const batches = await env.DB.prepare(`SELECT DISTINCT batch FROM licenses ORDER BY batch`).all();

  return json({
    keys: rows.results, counts,
    batches: (batches.results || []).map((r) => r.batch),
    page, per_page: perPage, total: countRow?.n ?? 0,
  }, 200, cors);
}

// ---------- admin: stats (dashboard) ----------
async function handleAdminStats(env, cors) {
  const totals = await env.DB.prepare(
    `SELECT COUNT(*) AS total,
            SUM(CASE WHEN status='unused'  THEN 1 ELSE 0 END) AS unused,
            SUM(CASE WHEN status='active'  THEN 1 ELSE 0 END) AS active,
            SUM(CASE WHEN status='revoked' THEN 1 ELSE 0 END) AS revoked,
            SUM(activation_count) AS total_activations
       FROM licenses`
  ).first();
  const byBatch = await env.DB.prepare(
    `SELECT batch, status, COUNT(*) AS count FROM licenses GROUP BY batch, status ORDER BY batch, status`
  ).all();
  const recent = await env.DB.prepare(
    `SELECT created_at, code_canon, device_name, email, outcome FROM activations
      ORDER BY id DESC LIMIT 25`
  ).all();
  return json({ totals, byBatch: byBatch.results, recentActivations: recent.results }, 200, cors);
}

// ---------- admin: generate (D1 batch chunked at 100/statement limit) ----------
async function handleAdminGenerate(req, env, cors) {
  let body = {};
  try { body = await req.json(); } catch { /* allow empty */ }
  const n = Math.min(Math.max(parseInt(body.n || '0', 10), 1), 500);
  const batch = String(body.batch || 'reddit-launch').slice(0, 64);
  const tier = ['paid', 'free'].includes(body.tier) ? body.tier : 'pro';
  const maxA = Math.min(Math.max(parseInt(body.max_activations || '2', 10), 1), 10);

  const created = [], stmts = [], seen = new Set();
  while (created.length < n) {
    const code = randomCode();
    const canon = canonicalizeCode(code);
    if (!canon || seen.has(canon)) continue;   // guard the vanishingly rare in-batch dup
    seen.add(canon);
    const id = randomId();
    created.push({ id, code });
    stmts.push(env.DB.prepare(
      `INSERT INTO licenses (id, code, code_canon, status, batch, tier, max_activations)
       VALUES (?, ?, ?, 'unused', ?, ?, ?)`
    ).bind(id, code, canon, batch, tier, maxA));
  }
  try {
    // D1 caps batch() at 100 statements — chunk, or large generates silently fail.
    for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
  } catch (e) {
    return json({ error: 'generate_failed', message: String(e).slice(0, 200) }, 500, cors);
  }
  return json({ created: created.length, keys: created, batch, tier, max_activations: maxA }, 200, cors);
}

// ---------- admin: revoke / unrevoke ----------
async function handleAdminRevoke(env, id, revoke, cors) {
  const res = await env.DB.prepare(
    revoke
      ? `UPDATE licenses SET status='revoked' WHERE id = ?`
      : `UPDATE licenses SET status = CASE WHEN activation_count > 0 THEN 'active' ELSE 'unused' END WHERE id = ?`
  ).bind(id).run();
  if ((res.meta?.changes ?? 0) === 0) return json({ error: 'not_found' }, 404, cors);
  const lic = await env.DB.prepare(`SELECT code_canon FROM licenses WHERE id = ?`).bind(id).first();
  await logActivation(env, {
    license_id: id, codeCanon: lic?.code_canon || '', deviceId: 'admin', deviceName: null,
    email: null, ipHash: null, outcome: revoke ? 'revoke' : 'unrevoke',
  });
  return json({ ok: true, id, status: revoke ? 'revoked' : 'restored' }, 200, cors);
}

// ---------- admin: CSV export (RFC 4180 escaping only when needed) ----------
async function handleAdminExport(env, url, cors) {
  const status = url.searchParams.get('status'), batch = url.searchParams.get('batch');
  const where = [], binds = [];
  if (status && status !== 'all') { where.push('status = ?'); binds.push(status); }
  if (batch && batch !== 'all')   { where.push('batch = ?');  binds.push(batch); }
  const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const rows = await env.DB.prepare(
    `SELECT code, status, batch, tier, email, activation_count, max_activations, activated_at, created_at
       FROM licenses ${clause} ORDER BY created_at ASC`
  ).bind(...binds).all();

  const esc = (v) => {
    const s = v == null ? '' : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const header = ['code','status','batch','tier','email','activation_count','max_activations','activated_at','created_at'];
  const lines = [header.join(',')];
  for (const r of rows.results) lines.push(header.map((h) => esc(r[h])).join(','));

  return new Response(lines.join('\n'), {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="simpledictation-keys-${nowISO().slice(0,10)}.csv"`,
      ...cors,
    },
  });
}

// ---------- entry ----------
export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const cors = corsHeaders(req, env);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    try {
      // public
      if (req.method === 'POST' && url.pathname === '/v1/activate') return handleActivate(req, env, cors);
      if (req.method === 'POST' && url.pathname === '/v1/validate') return handleValidate(req, env, cors);
      if (req.method === 'GET'  && url.pathname === '/')
        return json({ ok: true, service: 'simpledictation-license', kid: env.KID }, 200, cors);

      // admin
      if (url.pathname.startsWith('/admin/')) {
        if (!requireAdmin(req, env)) return json({ error: 'unauthorized' }, 401, cors);
        if (req.method === 'GET'  && url.pathname === '/admin/keys')          return handleAdminList(env, url, cors);
        if (req.method === 'GET'  && url.pathname === '/admin/stats')         return handleAdminStats(env, cors);
        if (req.method === 'GET'  && url.pathname === '/admin/export.csv')    return handleAdminExport(env, url, cors);
        if (req.method === 'POST' && url.pathname === '/admin/keys/generate') return handleAdminGenerate(req, env, cors);
        const m = url.pathname.match(/^\/admin\/keys\/([^/]+)\/(revoke|unrevoke)$/);
        if (req.method === 'POST' && m) return handleAdminRevoke(env, decodeURIComponent(m[1]), m[2] === 'revoke', cors);
        return json({ error: 'not_found' }, 404, cors);
      }

      return json({ error: 'not_found' }, 404, cors);
    } catch (e) {
      return json({ error: 'server_error', message: String((e && e.message) || e).slice(0, 300) }, 500, cors);
    }
  },
};
