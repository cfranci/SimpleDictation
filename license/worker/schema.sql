-- SimpleDictation license database (Cloudflare D1) -- SOURCE OF TRUTH for all keys.
-- Apply:      npx wrangler d1 execute simpledictation-licenses --remote --file=schema.sql
-- Idempotent: safe to re-run.
--
-- The licenses columns MATCH scripts/gen-keys.mjs dist/seed.sql exactly
-- (id, code, code_canon, status, batch, tier, email, max_activations,
--  activation_count, device_ids, created_at) or the committed seed INSERT fails.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS licenses (
  id               TEXT PRIMARY KEY,        -- 16-hex-char id from gen-keys (randomBytes(8).hex)
  code             TEXT NOT NULL UNIQUE,    -- pretty form for humans/Reddit, e.g. SD42-R2RD-ZGDP-AWAZ
  code_canon       TEXT NOT NULL UNIQUE,    -- canonical match key, e.g. SD42R2RDZGDPAWAZ (Worker SELECTs on this)
  status           TEXT NOT NULL DEFAULT 'unused'
                     CHECK (status IN ('unused','active','revoked')),
  batch            TEXT NOT NULL DEFAULT 'reddit-launch',
  tier             TEXT NOT NULL DEFAULT 'pro'     -- 'pro' (giveaway=full) | 'paid' (Stripe) | 'free'
                     CHECK (tier IN ('pro','paid','free')),
  email            TEXT,                    -- captured at activation if provided (optional)
  max_activations  INTEGER NOT NULL DEFAULT 2,     -- gen-keys default = 2 (laptop+desktop); revoke abusers
  activation_count INTEGER NOT NULL DEFAULT 0,
  device_ids       TEXT NOT NULL DEFAULT '[]',     -- JSON array of device_id strings seen
  note             TEXT,                    -- freeform admin note ("DM'd u/foo", "stripe pi_xxx")
  activated_at     TEXT,                    -- ISO8601 of FIRST activation
  created_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- One row per activation-related event (audit log + admin visibility).
CREATE TABLE IF NOT EXISTS activations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  license_id  TEXT REFERENCES licenses(id) ON DELETE CASCADE,  -- NULL for unknown-code attempts
  code_canon  TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  device_name TEXT,
  email       TEXT,
  ip_hash     TEXT,                         -- sha256(ip + IP_SALT) -- never a raw IP
  outcome     TEXT NOT NULL,                -- activated | reactivated | deactivated | rejected_cap | rejected_revoked | rejected_unknown | revoke | unrevoke
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Coarse per-IP rate-limit counter (fixed window). D1 only, no paid KV / Durable Objects.
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket     TEXT PRIMARY KEY,             -- "activate:<ip_hash>:<epoch_minute>"
  hits       INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL             -- unix seconds; rows past this are ignored + swept
);

CREATE INDEX IF NOT EXISTS idx_licenses_status   ON licenses(status);
CREATE INDEX IF NOT EXISTS idx_licenses_batch    ON licenses(batch);
CREATE INDEX IF NOT EXISTS idx_licenses_created  ON licenses(created_at);
CREATE INDEX IF NOT EXISTS idx_activations_lic   ON activations(license_id);
CREATE INDEX IF NOT EXISTS idx_activations_time  ON activations(created_at);
CREATE INDEX IF NOT EXISTS idx_ratelimits_expiry ON rate_limits(expires_at);
