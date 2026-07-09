#!/usr/bin/env node
// scripts/gen-keys.mjs
//
// SimpleDictation license key generator.
// Node built-in `crypto` only. No npm install, no dependencies.
//
// ---------------------------------------------------------------------------
// WHAT THIS RECONCILES
// ---------------------------------------------------------------------------
// The brief wants a SHORT human-typeable code AND offline Ed25519 verification.
// Those genuinely conflict: a raw Ed25519 signature is 64 bytes = 103 base32
// chars (measured), so no single typeable string can also be a self-verifying
// signature. This is resolved with the doc's two-token model:
//
//   1. The SHORT CODE  SD42-XXXX-XXXX-XXXX  is a 60-bit random D1 lookup key.
//      It is NOT a signature and NOT self-verifying. You post it on Reddit;
//      the user types it once.
//   2. ONLINE ACTIVATION (once): the app POSTs the code to the Worker. The
//      Worker looks it up in D1, enforces the single-use / max_activations cap,
//      records the device, then MINTS a fresh Ed25519-signed token bound to the
//      code and returns it.
//   3. OFFLINE FOREVER after: the app stores the signed token in UserDefaults
//      and verifies it locally on every launch with the embedded public key.
//      One network call in the app's entire life.
//
// This generator therefore SEEDS D1 WITH CODES ONLY. It does NOT pre-sign
// tokens. Minting happens at activation, where a seat is consumed and the
// device/email is known. (Pre-signing would let a scraped code carry a
// ready-made valid token that bypasses the activation gate, and a pre-minted
// token with email='' would not equal the Worker's re-mint once a buyer email
// is embedded — so we never pre-mint.)
//
// ---------------------------------------------------------------------------
// DELIBERATE DIVERGENCE FROM docs/LICENSING-PAYMENTS.md
// ---------------------------------------------------------------------------
// The doc assumes Lemon Squeezy issues the purchase key and the Worker calls the
// LS activate API. For the Reddit free-key batch (and Stripe Payment Link paid
// keys) there is no LS: the Worker + D1 IS the source of truth. So this script
// seeds D1 directly. The Ed25519 TOKEN LAYER IS KEPT EXACTLY AS THE DOC DEFINES
// IT so the existing Swift LicenseManager.verify() and Claim struct work
// unchanged:
//     Claim  = { v, kid, sku, email, order, iid }   (doc lines 190-191)
//     token  = SD1-<base32(payload)>.<base32(signature)>   (doc line 77)
// For self-issued keys, `order` and `iid` both carry the short code (there is no
// LS order/instance). The /deactivate route reads `iid` and, for self-issued
// keys, just clears the D1 activation row instead of calling LS.
//
// ---------------------------------------------------------------------------
// CRITICAL FIX TO THE DOC'S WORKER SNIPPET (doc line 368)
// ---------------------------------------------------------------------------
// The doc's Worker signs with:
//     crypto.subtle.importKey('raw', base32Decode(env.ED25519_PRIVATE_KEY_B64),
//                             { name:'Ed25519' }, false, ['sign'])
// VERIFIED LIVE (Node 22 = same WebCrypto standard as Cloudflare Workers): this
// FAILS with "Unsupported key usage for a Ed25519 key". WebCrypto supports 'raw'
// import for Ed25519 PUBLIC keys ONLY, never private keys.
// THE FIX (verified working): store the PRIVATE key as base32 of its PKCS8 DER
// and import it as 'pkcs8' in the Worker:
//     crypto.subtle.importKey('pkcs8', base32Decode(env.ED25519_PRIVATE_KEY_B64),
//                             { name:'Ed25519' }, false, ['sign'])
// The env var NAME stays ED25519_PRIVATE_KEY_B64; only its CONTENT (now base32 of
// PKCS8) and the import format ('pkcs8') change. This script prints exactly that
// value under "Worker secret ED25519_PRIVATE_KEY_B64".
//
// ---------------------------------------------------------------------------
// USAGE
// ---------------------------------------------------------------------------
//   node scripts/gen-keys.mjs                                  # 100 keys, today's batch
//   node scripts/gen-keys.mjs --count 50                       # 50 keys
//   node scripts/gen-keys.mjs --batch reddit-launch --tier pro --count 100
//   node scripts/gen-keys.mjs --max-activations 2              # 2 Macs per key
//   node scripts/gen-keys.mjs --self-test                      # prove mint<->verify + tamper reject
//   node scripts/gen-keys.mjs --verify SD1-...                 # decode/verify a real token off the wire
//
// OUTPUTS (dist/, gitignored):
//   dist/keys.jsonl       one JSON object per line — audit trail + D1 seed backup
//   dist/reddit-keys.txt  plain code list, one per line — the list to post
//   dist/seed.sql         ready-to-run D1 INSERTs (codes only, no tokens)

import {
  generateKeyPairSync, randomBytes, randomInt, sign, verify, webcrypto,
  createPublicKey, createPrivateKey,
} from 'node:crypto';
import { mkdirSync, existsSync, writeFileSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT      = join(__dirname, '..');
const KEYS_DIR  = join(ROOT, 'keys');
const DIST_DIR  = join(ROOT, 'dist');
const PRIV_PEM  = join(KEYS_DIR, 'ed25519_private.pem');

// Key id — bump this string if you ever rotate the signing key. The app can then
// verify old and new tokens by kid. Must match the Worker's payload kid. Keep it
// stable for one keypair. (Matches docs/LICENSING-PAYMENTS.md kid 'sd-2026-07'.)
const KID = 'sd-2026-07';
const SKU = 'simpledictation';
const TOKEN_VERSION = 1;

// ---------------------------------------------------------------------------
// Crockford Base32. Alphabet excludes I, L, O, U (ambiguity + accidental words).
// Decode folds I/L -> 1 and O -> 0 (a good-faith typo off a Reddit post survives)
// and REJECTS U (Crockford treats U as invalid; silently remapping it would
// mis-decode a token into a wrong-but-accepted byte string).
// This SAME alphabet + rules must be mirrored byte-for-byte in Sources/Base32.swift
// and in the Worker. If they drift, tokens silently fail to verify. Do not
// "improve" it in one place only.
// ---------------------------------------------------------------------------
const B32_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const B32_DECODE = Object.fromEntries([...B32_ALPHABET].map((c, i) => [c, i]));

function base32Encode(bytes) {
  let bits = 0, value = 0, out = '';
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) { out += B32_ALPHABET[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(str) {
  const norm = str.toUpperCase()
    .replace(/[IL]/g, '1')
    .replace(/O/g, '0')
    .replace(/[^0-9A-Z]/g, '');   // drop dashes, spaces, the SD42- prefix, etc.
  let bits = 0, value = 0;
  const out = [];
  for (const c of norm) {
    const d = B32_DECODE[c];      // U is not in the map -> returns undefined -> reject
    if (d === undefined) return null;
    value = (value << 5) | d;
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(out);
}

// ---------------------------------------------------------------------------
// Human-typeable code. 12 body chars from Crockford base32 = 60 bits of entropy.
// Format: SD42-XXXX-XXXX-XXXX  (SD42 = brand + the $4.20 meme, fixed literal).
// crypto.randomInt gives uniform, unbiased character selection.
// 60 bits is ample: 100 live keys / 2^60 ~= 8.7e-17 chance per brute-force guess;
// with the Worker rate limit, enumeration is a non-threat. Typeability wins over
// defending a $4.20 giveaway against a nation-state.
// ---------------------------------------------------------------------------
function makeCode() {
  let body = '';
  for (let i = 0; i < 12; i++) body += B32_ALPHABET[randomInt(32)];
  return `SD42-${body.slice(0, 4)}-${body.slice(4, 8)}-${body.slice(8, 12)}`;
}

// Canonical form the DB stores + the Worker matches on: strip dashes, uppercase,
// fold I/L->1 and O->0. So "sd42 r2rd zgdp awaz", "SD42-R2RD-ZGDP-AWAZ" and
// "SD42R2RDZGDPAWAZ" all resolve to ONE canonical key. The Worker canonicalizes
// the typed code the same way before SELECT ... WHERE code_canon = ?.
export function canonicalizeCode(code) {
  return code.toUpperCase().replace(/[IL]/g, '1').replace(/O/g, '0').replace(/[^0-9A-Z]/g, '');
}

// ---------------------------------------------------------------------------
// Ed25519 keypair. Node hands us DER/PEM; we extract the RAW 32-byte halves and
// also the full PKCS8 DER for the Worker secret.
//   raw public  = last 32 bytes of the 44-byte SPKI DER   (verified: SPKI == 44)
//   PKCS8 DER   = 48 bytes                                 (verified: PKCS8 == 48)
// - raw public (base64)  -> Swift LicenseManager.publicKeyB64
//                           CryptoKit Curve25519.Signing.PublicKey(rawRepresentation:)
// - base32(PKCS8 DER)    -> Worker secret ED25519_PRIVATE_KEY_B64
//                           WebCrypto importKey('pkcs8', base32Decode(secret), ...)
// ---------------------------------------------------------------------------
function loadOrCreateKeypair() {
  if (existsSync(PRIV_PEM)) {
    const priv = createPrivateKey({ key: readFileSync(PRIV_PEM), format: 'pem', type: 'pkcs8' });
    const pub  = createPublicKey(priv);
    return { priv, pub, created: false };
  }
  mkdirSync(KEYS_DIR, { recursive: true });
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  writeFileSync(PRIV_PEM, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  return { priv: privateKey, pub: publicKey, created: true };
}

function rawPublic(pub)      { const d = pub.export({ type: 'spki',  format: 'der' }); return d.subarray(d.length - 32); }
function pkcs8Der(priv)      { return priv.export({ type: 'pkcs8', format: 'der' }); }

// ---------------------------------------------------------------------------
// TOKEN LAYER — this is what the WORKER does at activation. Defined here so the
// crypto lives in exactly ONE place and the Swift verify can be checked against
// it. gen-keys.mjs does NOT mint tokens during batch generation; --self-test
// exercises this to prove sign<->verify agree before you trust the batch.
//
// Uses the SAME WebCrypto path the Worker uses (importKey('pkcs8', ...)) so the
// self-test proves the exact deploy path, not a look-alike.
//
// Token wire format:  SD1-<base32(payloadBytes)>.<base32(signatureBytes)>
// Payload schema is the doc's EXACT Claim: { v, kid, sku, email, order, iid }.
// Sign over the RAW payload bytes. Verify over the SAME raw bytes. Never
// re-serialize JSON at verify time (key ordering is not byte-stable — the
// MenuBarBuddy bug the doc flags). Swift JSONDecoder only DECODES, never
// re-encodes, so it is safe on the verify side.
// ---------------------------------------------------------------------------

// Fixed key insertion order — the Worker must serialize with this identical
// order to produce byte-identical tokens. Kept as insertion order (simple,
// matches the doc's Worker snippet) rather than a sort step.
function payloadBytesFor({ code, email = '' }) {
  const payload = JSON.stringify({
    v: TOKEN_VERSION,
    kid: KID,
    sku: SKU,
    email,
    order: code,   // self-issued: the short code stands in for the LS order_id
    iid: code,     // self-issued: the short code stands in for the LS instance.id
  });
  return Buffer.from(payload, 'utf8');
}

export async function mintToken(pkcs8Bytes, { code, email = '' }) {
  const bytes = payloadBytesFor({ code, email });
  const key = await webcrypto.subtle.importKey('pkcs8', pkcs8Bytes, { name: 'Ed25519' }, false, ['sign']);
  const sig = await webcrypto.subtle.sign('Ed25519', key, bytes);
  return `SD1-${base32Encode(bytes)}.${base32Encode(new Uint8Array(sig))}`;
}

// Mirror of the Swift verify — the app runs the CryptoKit equivalent of this
// (Curve25519.Signing.PublicKey.isValidSignature over the raw base32-decoded
// payload bytes). rawPub is the raw 32-byte public key.
export function verifyToken(rawPub, token) {
  if (typeof token !== 'string' || !token.startsWith('SD1-')) return null;
  const parts = token.slice(4).split('.');
  if (parts.length !== 2) return null;
  const payloadBytes = base32Decode(parts[0]);
  const sig = base32Decode(parts[1]);
  if (!payloadBytes || !sig || sig.length !== 64) return null;
  // Node classic verify with the raw public key wrapped in the fixed SPKI header.
  const spki = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), rawPub]);
  const pubKey = { key: spki, format: 'der', type: 'spki' };
  if (!verify(null, payloadBytes, pubKey, sig)) return null;
  let claim;
  try { claim = JSON.parse(payloadBytes.toString('utf8')); } catch { return null; }
  if (claim.sku !== SKU) return null;
  return claim;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const a = {
    count: 100,
    batch: `reddit-${new Date().toISOString().slice(0, 10)}`,
    tier: 'pro',
    maxActivations: 2,   // 2 Macs per key: a normal user's laptop + desktop, without needing two Reddit keys
    verify: null,
    selfTest: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if      (k === '--count')            a.count = parseInt(argv[++i], 10);
    else if (k === '--batch')            a.batch = argv[++i];
    else if (k === '--tier')             a.tier = argv[++i];
    else if (k === '--max-activations')  a.maxActivations = parseInt(argv[++i], 10);
    else if (k === '--verify')           a.verify = argv[++i];
    else if (k === '--self-test')        a.selfTest = true;
  }
  return a;
}

function sqlEscape(s) { return String(s).replace(/'/g, "''"); }

async function main() {
  const args = parseArgs(process.argv);
  const { priv, pub, created } = loadOrCreateKeypair();

  const rawPub  = rawPublic(pub);
  const pkcs8   = pkcs8Der(priv);

  if (created) {
    console.log('\n=== NEW Ed25519 keypair created ===');
    console.log(`  Private PEM: ${PRIV_PEM}  (mode 600, gitignored)`);
    console.log('  BACK THIS FILE UP OFFLINE. Lose it and you cannot mint tokens for these keys.\n');
  } else {
    console.log(`\nUsing existing keypair at ${PRIV_PEM}\n`);
  }

  console.log('--- Paste into Sources/LicenseManager.swift (publicKeyB64) ---');
  console.log(`  private static let publicKeyB64 = "${rawPub.toString('base64')}"`);
  console.log('\n--- Set the Worker signing secret (base32 of the PKCS8 DER) ---');
  console.log('  wrangler secret put ED25519_PRIVATE_KEY_B64   # paste the value below:');
  console.log(`  ${base32Encode(pkcs8)}`);
  console.log('  (Worker imports this with importKey("pkcs8", base32Decode(secret), ...). NEVER commit it.)\n');

  // --verify: decode a real token off the wire and check it (ops sanity tool)
  if (args.verify) {
    console.log('verifyToken ->', verifyToken(rawPub, args.verify));
    return;
  }

  // --self-test: prove mint<->verify agree end to end via the EXACT Worker path
  if (args.selfTest) {
    const tok  = await mintToken(pkcs8, { code: 'SD42-SELF-TEST-0000', email: 'a@b.co' });
    const ok   = verifyToken(rawPub, tok);
    console.log('SELF-TEST token :', tok.slice(0, 52) + '...');
    console.log('SELF-TEST verify:', ok ? 'PASS' : 'FAIL', ok ? JSON.stringify(ok) : '');
    const bad = tok.slice(0, -2) + (tok.endsWith('0') ? '11' : '00');
    console.log('SELF-TEST tamper rejected:', verifyToken(rawPub, bad) === null ? 'PASS' : 'FAIL');
    if (!ok) process.exit(1);
    return;
  }

  // Batch generate codes (codes only — no tokens seeded)
  mkdirSync(DIST_DIR, { recursive: true });
  const now = new Date().toISOString();
  const seen = new Set();
  const rows = [];
  while (rows.length < args.count) {
    const code = makeCode();
    const canon = canonicalizeCode(code);
    if (seen.has(canon)) continue;            // guard the astronomically-rare dupe
    seen.add(canon);
    rows.push({
      id: randomBytes(8).toString('hex'),     // 16-hex-char D1 primary key
      code,                                    // pretty form for humans/Reddit
      code_canon: canon,                       // what the Worker matches on
      status: 'unused',
      batch: args.batch,
      tier: args.tier,
      email: null,
      max_activations: args.maxActivations,
      activation_count: 0,
      created_at: now,
    });
  }

  // SAFETY GATE: prove the crypto works end-to-end before we emit anything.
  // Mint + verify + tamper-reject via the exact Worker path. If ANY step fails,
  // abort with exit 1 so a cryptographically broken batch is never posted/seeded.
  {
    const probe = rows[0].code;
    const tok = await mintToken(pkcs8, { code: probe, email: '' });
    const claim = verifyToken(rawPub, tok);
    const tampered = tok.slice(0, -2) + (tok.endsWith('0') ? '11' : '00');
    const tamperRejected = verifyToken(rawPub, tampered) === null;
    if (!claim || claim.order !== probe || claim.iid !== probe || !tamperRejected) {
      console.error('\nSAFETY GATE FAILED: mint/verify/tamper self-check did not pass. Aborting; nothing written.');
      process.exit(1);
    }
    console.log('Safety gate: mint -> verify -> tamper-reject PASS (Worker path).');
  }

  // dist/keys.jsonl — audit + backup (also usable to re-derive seed.sql)
  writeFileSync(join(DIST_DIR, 'keys.jsonl'), rows.map(r => JSON.stringify(r)).join('\n') + '\n', { mode: 0o600 });

  // dist/reddit-keys.txt — plain list to paste
  writeFileSync(join(DIST_DIR, 'reddit-keys.txt'), rows.map(r => r.code).join('\n') + '\n');

  // dist/seed.sql — direct D1 insert (matches backend-worker schema.sql columns), CODES ONLY
  const sql = rows.map(r =>
    `INSERT INTO licenses (id, code, code_canon, status, batch, tier, email, max_activations, activation_count, device_ids, created_at) ` +
    `VALUES ('${r.id}', '${sqlEscape(r.code)}', '${r.code_canon}', 'unused', '${sqlEscape(r.batch)}', '${sqlEscape(r.tier)}', NULL, ${r.max_activations}, 0, '[]', '${r.created_at}');`
  ).join('\n');
  writeFileSync(join(DIST_DIR, 'seed.sql'), sql + '\n', { mode: 0o600 });

  console.log(`\nGenerated ${rows.length} keys  (batch="${args.batch}", tier="${args.tier}", max_activations=${args.maxActivations})`);
  console.log('  dist/keys.jsonl      -> audit + backup');
  console.log('  dist/reddit-keys.txt -> the list to post');
  console.log('  dist/seed.sql        -> wrangler d1 execute simpledictation-licenses --file dist/seed.sql --remote');
  console.log(`  sample code: ${rows[0].code}\n`);
}

main().catch((e) => { console.error(e); process.exit(1); });
