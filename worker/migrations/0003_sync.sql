-- Device sync ("Konto & Geräte"): one opaque JSON document per account.
-- Rows are deleted explicitly by the worker; no foreign-key cascades.
CREATE TABLE IF NOT EXISTS sync_accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  recovery_hash TEXT NOT NULL UNIQUE,
  data TEXT,
  revision INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_devices (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sync_devices_account ON sync_devices(account_id);
CREATE TABLE IF NOT EXISTS sync_pairings (
  code_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sync_pairings_account ON sync_pairings(account_id);
