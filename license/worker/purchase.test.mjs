// Purchase path: signed checkout.session.completed -> one key -> buyer email ->
// /v1/order -> /v1/activate -> the same offline checks LicenseManager.verifyToken does.
//
// Run from the repo root: node --test license/worker/purchase.test.mjs
//
// The app check lives in Sources/LicenseManager.swift (verifyToken): the token must
// start with "SD1-", both segments are Crockford base32, Ed25519 verifies over the
// exact payload bytes, and the claim is { v:1, sku:"simpledictation", order, iid }
// with order == iid == the pretty code. This file runs that check in WebCrypto
// because the Swift type is AppKit/IOKit and does not build on Linux CI.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker, { base32Decode, verifyStripeSignature } from './worker.js';

const SECRET = 'whsec_test_secret';
const PLINK = 'plink_test_simpledictation';
const BUYER = 'buyer@example.com';

const B32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function base32Encode(bytes) {
  let bits = 0, value = 0, out = '';
  for (let i = 0; i < bytes.length; i++) {
    value = (value << 8) | bytes[i]; bits += 8;
    while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

const { publicKey, privateKey } = await crypto.subtle.generateKey(
  { name: 'Ed25519' }, true, ['sign', 'verify']);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', privateKey));
const rawPub = new Uint8Array(await crypto.subtle.exportKey('raw', publicKey));
assert.equal(pkcs8.length, 48);
const PRIVATE_B32 = base32Encode(pkcs8);

// In-memory stand-in for the D1 statements the purchase and activate paths use.
class FakeD1 {
  constructor() { this.licenses = []; this.rate = new Map(); }
  prepare(sql) {
    const q = sql.replace(/\s+/g, ' ').trim();
    return { bind: (...args) => ({
      first: async () => this.#first(q, args),
      run: async () => this.#run(q, args),
      all: async () => ({ results: [] }),
    }) };
  }
  #first(q, args) {
    if (q.startsWith('SELECT code FROM licenses WHERE note')) {
      const row = this.licenses.find((l) => l.note === args[0]);
      return row ? { code: row.code } : null;
    }
    if (q.startsWith('SELECT * FROM licenses WHERE code_canon')) {
      return this.licenses.find((l) => l.code_canon === args[0]) || null;
    }
    if (q.startsWith('SELECT hits FROM rate_limits')) {
      return { hits: this.rate.get(args[0]) || 0 };
    }
    throw new Error('unhandled SELECT: ' + q);
  }
  #run(q, args) {
    if (q.startsWith('INSERT INTO rate_limits')) {
      const bucket = args[0];
      this.rate.set(bucket, (this.rate.get(bucket) || 0) + 1);
      return { meta: { changes: 1 } };
    }
    if (q.startsWith('DELETE FROM rate_limits')) return { meta: { changes: 0 } };
    if (q.startsWith('INSERT INTO activations')) return { meta: { changes: 1 } };
    if (q.startsWith('INSERT INTO licenses')) {
      const [id, code, canon, email, note, noteGuard] = args;
      if (note !== noteGuard) throw new Error('test insert bind mismatch');
      if (this.licenses.some((l) => l.note === note)) return { meta: { changes: 0 } };
      if (this.licenses.some((l) => l.code === code || l.code_canon === canon)) {
        throw new Error('UNIQUE constraint failed: licenses.code');
      }
      this.licenses.push({
        id, code, code_canon: canon, status: 'unused', batch: 'stripe', tier: 'paid',
        email, max_activations: 2, activation_count: 0, device_ids: '[]', note,
      });
      return { meta: { changes: 1 } };
    }
    if (q.startsWith('UPDATE licenses')) {
      const [count, devices, email, activated, id] = args;
      const row = this.licenses.find((l) => l.id === id);
      if (!row) return { meta: { changes: 0 } };
      row.status = 'active';
      row.activation_count = count;
      row.device_ids = devices;
      if (email) row.email = email;
      row.activated_at = row.activated_at || activated;
      return { meta: { changes: 1 } };
    }
    throw new Error('unhandled SQL: ' + q);
  }
}

function envFor(db, { emailStatus = 200, allowTest = false, secret = SECRET, link = PLINK } = {}) {
  return {
    DB: db,
    ED25519_PRIVATE_KEY_B64: PRIVATE_B32,
    KID: 'sd-2026-07',
    SKU: 'simpledictation',
    STRIPE_WEBHOOK_SECRET: secret,
    STRIPE_PAYMENT_LINK: link,
    STRIPE_ALLOW_TEST_MODE: allowTest ? '1' : '',
    RESEND_API_KEY: 're_test',
    ALERT_FROM: 'SimpleDictation <keys@example.com>',
    ALERT_EMAIL: 'owner@example.com',
    DOWNLOAD_URL: 'https://github.com/cfranci/SimpleDictation/releases/download/v1.4.0/SimpleDictation-1.4.0.dmg',
    RATE_LIMIT_PER_MIN: '8',
    ALLOWED_ORIGINS: 'https://cfranci.github.io',
    _emailStatus: emailStatus,
  };
}

function sessionEvent({
  id, type = 'checkout.session.completed', paid = true, link = PLINK,
  email = BUYER, livemode = true,
} = {}) {
  return JSON.stringify({
    id: 'evt_' + id,
    object: 'event',
    type,
    livemode,
    data: { object: {
      id, object: 'checkout.session', payment_link: link,
      payment_status: paid ? 'paid' : 'unpaid',
      customer_details: email ? { email } : {},
      customer_email: email || null,
    } },
  });
}

async function sign(raw, secret = SECRET, t = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${t}.${raw}`));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `t=${t},v1=${hex}`;
}

async function postWebhook(env, raw, header) {
  return worker.fetch(new Request('https://simpledictation-licenses.api-king.workers.dev/v1/stripe/webhook', {
    method: 'POST',
    headers: { 'Stripe-Signature': header, 'Content-Type': 'application/json' },
    body: raw,
  }), env);
}

// LicenseManager.verifyToken, minus the Swift types.
async function appAcceptsToken(token) {
  if (!token.startsWith('SD1-')) return null;
  const parts = token.slice(4).split('.');
  if (parts.length !== 2) return null;
  let payload, sig;
  try { payload = base32Decode(parts[0]); sig = base32Decode(parts[1]); }
  catch { return null; }
  const pub = await crypto.subtle.importKey('raw', rawPub, { name: 'Ed25519' }, false, ['verify']);
  const ok = await crypto.subtle.verify('Ed25519', pub, sig, payload);
  if (!ok) return null;
  const claim = JSON.parse(new TextDecoder().decode(payload));
  if (claim.v !== 1 || claim.sku !== 'simpledictation') return null;
  if (!claim.order || claim.order !== claim.iid) return null;
  for (const key of ['v', 'kid', 'sku', 'email', 'order', 'iid']) {
    if (!(key in claim)) return null;
  }
  return claim;
}

let emails;
const realFetch = globalThis.fetch;
test.beforeEach(() => { emails = []; });
test.after(() => { globalThis.fetch = realFetch; });

function installResend(status = 200) {
  globalThis.fetch = async (url, init) => {
    assert.equal(String(url), 'https://api.resend.com/emails');
    emails.push(JSON.parse(init.body));
    return new Response('{}', { status });
  };
}

test('checkout.session.completed mints one key, emails it, and the app accepts activation', async () => {
  installResend(200);
  const db = new FakeD1();
  const env = envFor(db);
  const raw = sessionEvent({ id: 'cs_live_paid_session_123456' });
  // Trailing newline on the secret is what a bad paste produces. The handler trims.
  env.STRIPE_WEBHOOK_SECRET = SECRET + '\n';
  env.STRIPE_PAYMENT_LINK = PLINK + ' ';

  const res = await postWebhook(env, raw, await sign(raw));
  assert.equal(res.status, 200);
  assert.equal(await res.text(), 'fulfilled');
  assert.equal(db.licenses.length, 1);
  const code = db.licenses[0].code;
  assert.match(code, /^SD42-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/);
  assert.equal(db.licenses[0].tier, 'paid');
  assert.equal(db.licenses[0].max_activations, 2);
  assert.equal(db.licenses[0].email, BUYER);
  assert.equal(db.licenses[0].note, 'stripe cs_live_paid_session_123456');

  assert.equal(emails.length, 1);
  assert.equal(emails[0].to[0], BUYER);
  assert.match(emails[0].text, new RegExp(code.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(emails[0].text, /v1\.4\.0/);

  // Thank-you page polls /v1/order?session= after reading Stripe's session_id param.
  const order = await worker.fetch(new Request(
    'https://simpledictation-licenses.api-king.workers.dev/v1/order?session=cs_live_paid_session_123456'
  ), env);
  assert.equal(order.status, 200);
  const shown = await order.json();
  assert.equal(shown.code, code);

  // Same lookup Stripe's own query name uses, in case a client forwards it raw.
  const orderByStripeName = await worker.fetch(new Request(
    'https://simpledictation-licenses.api-king.workers.dev/v1/order?session_id=cs_live_paid_session_123456'
  ), env);
  assert.equal((await orderByStripeName.json()).code, code);

  // In-app activation: one online call, then offline Ed25519 verification.
  const act = await worker.fetch(new Request('https://simpledictation-licenses.api-king.workers.dev/v1/activate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, device_id: 'CLEAN-MAC', email: '' }),
  }), env);
  assert.equal(act.status, 200);
  const body = await act.json();
  assert.equal(body.email, BUYER);
  assert.equal(body.max_activations, 2);
  const claim = await appAcceptsToken(body.token);
  assert.ok(claim, 'LicenseManager.verifyToken would reject this token');
  assert.equal(claim.order, code);
  assert.equal(claim.iid, code);
  assert.equal(claim.kid, 'sd-2026-07');
  assert.equal(claim.email, BUYER);

  // Flip the first signature character. The final base32 char is often only
  // padding bits, so changing it can leave the decoded signature untouched.
  const dot = body.token.indexOf('.');
  const at = dot + 1;
  const flipped = body.token[at] === '0' ? '1' : '0';
  const tampered = body.token.slice(0, at) + flipped + body.token.slice(at + 1);
  assert.equal(await appAcceptsToken(tampered), null);

  // A second delivery of the same event must not mint a second key.
  const again = await postWebhook(env, raw, await sign(raw));
  assert.equal(again.status, 200);
  assert.equal(db.licenses.length, 1);
  assert.equal(emails.at(-1).text.includes(code), true);
});

test('a failed buyer email is a 500, and the Stripe retry sends the same key', async () => {
  const db = new FakeD1();
  const env = envFor(db);
  const raw = sessionEvent({ id: 'cs_live_retry_session_12345' });
  installResend(403);
  const first = await postWebhook(env, raw, await sign(raw));
  assert.equal(first.status, 500);
  assert.equal(db.licenses.length, 1);
  const code = db.licenses[0].code;
  assert.equal(emails.filter((m) => m.to[0] === BUYER).length, 1);
  assert.equal(emails.some((m) => m.to[0] === 'owner@example.com'), true);

  installResend(200);
  const second = await postWebhook(env, raw, await sign(raw));
  assert.equal(second.status, 200);
  assert.equal(await second.text(), 'fulfilled');
  assert.equal(db.licenses.length, 1);
  const buyerMails = emails.filter((m) => m.to[0] === BUYER);
  assert.equal(buyerMails.length, 2);
  assert.match(buyerMails[1].text, new RegExp(code));
});

test('async_payment_succeeded fulfils a delayed payment, and unpaid completed does not', async () => {
  installResend(200);
  const db = new FakeD1();
  const env = envFor(db);
  const unpaid = sessionEvent({ id: 'cs_live_bank_session_123456', paid: false });
  const pending = await postWebhook(env, unpaid, await sign(unpaid));
  assert.equal(pending.status, 200);
  assert.equal(await pending.text(), 'ignored: unpaid');
  assert.equal(db.licenses.length, 0);

  const paid = sessionEvent({
    id: 'cs_live_bank_session_123456', type: 'checkout.session.async_payment_succeeded',
  });
  const done = await postWebhook(env, paid, await sign(paid));
  assert.equal(done.status, 200);
  assert.equal(db.licenses.length, 1);
  assert.equal(emails[0].to[0], BUYER);
});

test('bad signature, another product, and test mode do not mint a key', async () => {
  installResend(200);
  const db = new FakeD1();
  const env = envFor(db);
  const raw = sessionEvent({ id: 'cs_live_other_session_12345' });

  const bad = await postWebhook(env, raw, await sign(raw, 'whsec_wrong'));
  assert.equal(bad.status, 400);

  const other = sessionEvent({ id: 'cs_live_other_session_12345', link: 'plink_someone_else' });
  const ignored = await postWebhook(env, other, await sign(other));
  assert.equal(ignored.status, 200);
  assert.equal(await ignored.text(), 'ignored: other product');

  const testMode = sessionEvent({ id: 'cs_test_mode_session_123456', livemode: false });
  const liveOnly = await postWebhook(env, testMode, await sign(testMode));
  assert.equal(liveOnly.status, 200);
  assert.equal(await liveOnly.text(), 'ignored: test mode');
  assert.equal(db.licenses.length, 0);
  assert.equal(emails.length, 0);

  env.STRIPE_ALLOW_TEST_MODE = '1';
  const allowed = await postWebhook(env, testMode, await sign(testMode));
  assert.equal(allowed.status, 200);
  assert.equal(await allowed.text(), 'fulfilled');
  assert.equal(db.licenses.length, 1);
});

test('verifyStripeSignature rejects a stale timestamp', async () => {
  const raw = '{}';
  const old = await sign(raw, SECRET, Math.floor(Date.now() / 1000) - 600);
  assert.equal(await verifyStripeSignature(raw, old, SECRET), false);
  assert.equal(await verifyStripeSignature(raw, await sign(raw), SECRET), true);
});

test('the thank-you page reads the session_id Stripe actually appends', () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const html = readFileSync(join(here, '../../site/thanks.html'), 'utf8');
  assert.match(html, /params\.get\("session_id"\)/);
  assert.match(html, /\/v1\/order\?session=/);
});
