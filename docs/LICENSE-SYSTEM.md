# SimpleDictation License System

A self-issued license backend for the Reddit giveaway and Stripe buyers. No Lemon Squeezy.

## Architecture (5 lines)

1. `scripts/gen-keys.mjs` mints an Ed25519 keypair and seeds D1 with short codes (`SD42-XXXX-XXXX-XXXX`), one row per key. It never signs tokens.
2. A Cloudflare Worker (`simpledictation-licenses`, account API KING) holds the private key as a secret and owns a D1 database (also `simpledictation-licenses`) that is the source of truth for every key.
3. The user pastes a short code once. The app POSTs it to `POST /v1/activate`; the Worker looks it up by `code_canon`, enforces `activation_count < max_activations`, records the device, and mints a fresh Ed25519 token `SD1-<base32(payload)>.<base32(sig)>`.
4. The app verifies that token offline forever with the embedded public key (`Sources/LicenseManager.swift`). One network call in the app's entire life.
5. `admin/keys.html` is a single-file console over the Worker's `/admin` endpoints for listing, generating, revoking, and exporting keys.

The canonical token payload is `{ v, kid, sku, email, order, iid }` with `kid = "sd-2026-07"`, `sku = "simpledictation"`, `v = 1`, and for self-issued keys `order == iid == the short code`. Default `max_activations` is 2 (laptop plus desktop).

## Regenerate the 100 keys

```bash
node scripts/gen-keys.mjs --self-test         # prove mint/verify/tamper before trusting a batch
node scripts/gen-keys.mjs --batch reddit-launch --tier pro --count 100
```

This writes three gitignored files under `dist/`:

- `dist/reddit-keys.txt` the 100 plain codes to paste into Reddit.
- `dist/seed.sql` the D1 INSERTs (codes only, columns match `worker/schema.sql`).
- `dist/keys.jsonl` audit trail and backup.

The generator also prints two values:

- `private static let publicKeyB64 = "..."` (base64 raw public key). Already embedded in `Sources/LicenseManager.swift` for the current keypair (`g0917Ql8Kfp6mEGt5k23rlbTdLrmyyQ4iiOdOJK3of0=`). If you generate a NEW keypair, paste the new value there.
- The base32 PKCS8 private key for the Worker secret (see deploy step). This stays in `keys/` (gitignored) and is NEVER committed.

## Deploy (API KING)

Run these from the repo root. Use the API KING Cloudflare API token.

```bash
export CLOUDFLARE_API_TOKEN=<the API KING token>
cd worker

# 1. Create the D1 database, then paste the printed database_id into wrangler.jsonc (database_id field).
npx wrangler d1 create simpledictation-licenses

# 2. Apply the schema to the remote (real) database.
npx wrangler d1 execute simpledictation-licenses --file schema.sql --remote

# 3. Load the 100 keys generated above.
npx wrangler d1 execute simpledictation-licenses --file ../dist/seed.sql --remote

# 4. Set the two secrets (never committed).
#    Value = the base32 PKCS8 line the generator printed, kept in keys/ (gitignored).
npx wrangler secret put ED25519_PRIVATE_KEY_B64
#    Value = a long random string, e.g. openssl rand -base64 32
npx wrangler secret put ADMIN_TOKEN
#    Optional: IP_SALT (openssl rand -hex 16) for hashed IPs in the audit log.
#    Optional: PUBLIC_KEY (base32 raw public key) only if you want /v1/validate to verify signatures.

# 5. Deploy.
npx wrangler deploy
```

After deploy, confirm the printed URL matches `LicenseManager.workerBaseURL`
(`https://simpledictation-licenses.api-king.workers.dev`). If Cloudflare gives a different
subdomain, update that constant in `Sources/LicenseManager.swift` and the gate default in
`admin/keys.html`.

Quick sanity checks:

```bash
curl https://simpledictation-licenses.api-king.workers.dev/
npx wrangler d1 execute simpledictation-licenses --remote \
  --command "SELECT status, COUNT(*) FROM licenses GROUP BY status;"
```

## Operate the admin page

1. Open `admin/keys.html` in a browser (double-click the file, or serve it from the same origin as the Worker to avoid CORS).
2. Confirm the Worker base URL (defaults to `https://simpledictation-licenses.api-king.workers.dev`).
3. Paste the `ADMIN_TOKEN` you set above and click Unlock. The token is held in this tab only (sessionStorage); Lock wipes it.

From the console you can:

- See summary counts (total, redeemed, unused left, revoked).
- Search and filter by status and batch.
- Copy a single code, or "Copy unused as Reddit list" to grab every unused code at once.
- Export CSV.
- Revoke or restore any key.
- "Generate N more" to mint additional codes straight into D1.

## Redemption flow the user follows

1. Grab a code from the Reddit thread or a receipt (looks like `SD42-XXXX-XXXX-XXXX`).
2. Click the menu bar mic icon, choose "Enter License", paste the code, click Activate.
3. The app activates once online, verifies the returned token locally, and stores it.
4. It works offline from then on. No further network calls for licensing.

Codes activate on up to `max_activations` Macs (default 2). Re-activating the same Mac is idempotent and burns no seat. Buyers reach the paid build at the Stripe link `https://buy.stripe.com/4gMdR987h9mtchK2sCg360q`. Support: chaseefrancis1@gmail.com.
