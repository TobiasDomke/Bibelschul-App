import type { D1Database, RateLimit } from "@cloudflare/workers-types";
import { digest, readLimitedText, tokenPattern, type Env } from "./index";

// Device sync ("Konto & Geräte"): one person, several devices. No email or
// password: an account is created on the first device, further devices are
// linked with a short-lived pairing code and a recovery code restores access.
// A device is identified by the hash of its installation token. The server
// stores one opaque JSON document per account; the client merges, and the
// revision number gives optimistic concurrency.

type SyncEnv = Env & { SYNC_LIMIT?: RateLimit };

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const PAIRING_LENGTH = 8;
const RECOVERY_LENGTH = 24;
const pairingPattern = new RegExp(`^[${CODE_ALPHABET}]{${PAIRING_LENGTH}}$`);
const recoveryPattern = new RegExp(`^[${CODE_ALPHABET}]{${RECOVERY_LENGTH}}$`);
const deviceIdPattern = /^[0-9a-f]{24}$/;
export const PAIRING_TTL = 10 * 60 * 1000;
export const MAX_DEVICES = 10;
export const MAX_ACCOUNTS = 20000;
export const MAX_SYNC_BODY = 1_100_000;
export const MAX_DATA_BYTES = 1_000_000;
const MAX_JSON_BODY = 4096;
// C0/C1 controls, line/paragraph separators, bidi overrides/isolates and
// lone surrogates.
const controlPattern = /[\p{Cc}\p{Cs}\u2028\u2029\u202A-\u202E\u2066-\u2069]/u;
const loneSurrogate = /\p{Cs}/u;

class SyncError extends Error {
  constructor(
    readonly code: string,
    readonly status = 400,
  ) {
    super(code);
  }
}

interface Linked {
  device_id: string;
  device_name: string;
  account_id: string;
  account_name: string;
  created_at: number;
  devices: number;
}
interface AccountData {
  revision: number;
  updated_at: number;
  data: string | null;
}

export function isSyncPath(path: string) {
  return path === "/sync" || path.startsWith("/sync/");
}

function randomHex(bytes: number) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
}
function randomCode(length: number) {
  let code = "";
  // Rejection sampling keeps every character equally likely.
  const limit = 256 - (256 % CODE_ALPHABET.length);
  while (code.length < length) {
    for (const b of crypto.getRandomValues(new Uint8Array(32))) {
      if (b < limit && code.length < length)
        code += CODE_ALPHABET[b % CODE_ALPHABET.length];
    }
  }
  return code;
}
const group = (code: string) => code.match(/.{1,4}/g)!.join("-");
const pairingHash = (code: string) => digest("sync-pairing:" + code);
const recoveryHash = (code: string) => digest("sync-recovery:" + code);

/** Accepts "abcd-efgh", "ABCD EFGH", "...#verbinden=ABCD-EFGH" and "...?code=ABCD-EFGH". */
export function normalizePairingCode(value: string) {
  if (value.length > 512) return null;
  let raw = value.trim();
  const part = /(?:^|[?&#])(?:verbinden|code)=([^&#]*)/i.exec(raw)?.[1];
  if (part !== undefined) {
    try {
      raw = decodeURIComponent(part.replace(/\+/g, " "));
    } catch {
      return null;
    }
  }
  const code = raw.toUpperCase().replace(/[\s-]/g, "");
  return pairingPattern.test(code) ? code : null;
}
export function normalizeRecoveryCode(value: string) {
  if (value.length > 128) return null;
  const code = value.toUpperCase().replace(/[\s-]/g, "");
  return recoveryPattern.test(code) ? code : null;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function parseName(value: unknown, error: string) {
  if (typeof value !== "string" || value.length > 160)
    throw new SyncError(error);
  const text = value.trim();
  const length = [...text].length;
  if (length < 1 || length > 40 || controlPattern.test(text))
    throw new SyncError(error);
  return text;
}
function parseData(value: unknown) {
  if (typeof value !== "string" || loneSurrogate.test(value))
    throw new SyncError("invalid_data");
  const bytes = new TextEncoder().encode(value).byteLength;
  if (bytes > MAX_DATA_BYTES) throw new SyncError("too_large", 413);
  if (bytes < 2) throw new SyncError("invalid_data");
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new SyncError("invalid_data");
  }
  if (!isObject(parsed)) throw new SyncError("invalid_data");
  return value;
}

async function readJson(request: Request, allowed: string[], max = MAX_JSON_BODY) {
  if (!request.headers.get("Content-Type")?.startsWith("application/json"))
    throw new SyncError("unsupported_media_type", 415);
  const text = await readLimitedText(request, max);
  if (text === null) throw new SyncError("too_large", 413);
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new SyncError("invalid_request");
  }
  if (!isObject(body) || Object.keys(body).some((k) => !allowed.includes(k)))
    throw new SyncError("invalid_request");
  return body;
}
/** Endpoints without a request body still refuse oversized uploads. */
async function discardBody(request: Request) {
  if ((await readLimitedText(request, MAX_JSON_BODY)) === null)
    throw new SyncError("too_large", 413);
}

async function count(db: D1Database, sql: string, ...values: unknown[]) {
  const row = await db
    .prepare(sql)
    .bind(...values)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function linked(db: D1Database, tokenHash: string) {
  return db
    .prepare(
      `SELECT d.id AS device_id, d.name AS device_name, a.id AS account_id, a.name AS account_name,
      a.created_at AS created_at,
      (SELECT COUNT(*) FROM sync_devices x WHERE x.account_id = a.id) AS devices
      FROM sync_devices d JOIN sync_accounts a ON a.id = d.account_id WHERE d.token_hash = ?`,
    )
    .bind(tokenHash)
    .first<Linked>();
}
async function requireLinked(db: D1Database, tokenHash: string) {
  const row = await linked(db, tokenHash);
  if (!row) throw new SyncError("not_linked", 404);
  return row;
}
function accountView(row: Linked) {
  return {
    id: row.account_id,
    name: row.account_name,
    deviceId: row.device_id,
    deviceName: row.device_name,
    createdAt: row.created_at,
    devices: row.devices,
  };
}
async function accountData(db: D1Database, accountId: string) {
  const row = await db
    .prepare("SELECT revision, updated_at, data FROM sync_accounts WHERE id = ?")
    .bind(accountId)
    .first<AccountData>();
  if (!row) throw new SyncError("not_linked", 404);
  return row;
}
/** Device rows whose account is gone would block the token from linking again. */
function orphanCleanup(db: D1Database, tokenHash: string) {
  return db
    .prepare(
      `DELETE FROM sync_devices WHERE token_hash = ?
      AND NOT EXISTS (SELECT 1 FROM sync_accounts a WHERE a.id = sync_devices.account_id)`,
    )
    .bind(tokenHash);
}

async function createAccount(
  request: Request,
  db: D1Database,
  tokenHash: string,
  now: number,
) {
  const body = await readJson(request, ["name", "deviceName"]);
  const name = parseName(body.name, "invalid_name");
  const deviceName = parseName(body.deviceName, "invalid_device_name");
  if (await linked(db, tokenHash)) throw new SyncError("already_linked", 409);
  if (
    (await count(db, "SELECT COUNT(*) AS count FROM sync_accounts")) >=
    MAX_ACCOUNTS
  )
    throw new SyncError("capacity_reached", 503);
  const id = randomHex(16);
  const recoveryCode = randomCode(RECOVERY_LENGTH);
  try {
    await db.batch([
      orphanCleanup(db, tokenHash),
      db
        .prepare(
          `INSERT INTO sync_accounts (id, name, recovery_hash, data, revision, updated_at, created_at)
          VALUES (?, ?, ?, NULL, 0, ?, ?)`,
        )
        .bind(id, name, await recoveryHash(recoveryCode), now, now),
      db
        .prepare(
          `INSERT INTO sync_devices (id, account_id, token_hash, name, created_at, last_seen)
          VALUES (?, ?, ?, ?, ?, ?)`,
        )
        .bind(randomHex(12), id, tokenHash, deviceName, now, now),
    ]);
  } catch (error) {
    // A concurrent request linked this token first; the batch rolled back.
    if (await linked(db, tokenHash)) throw new SyncError("already_linked", 409);
    throw error;
  }
  const row = await requireLinked(db, tokenHash);
  return { account: accountView(row), recoveryCode: group(recoveryCode) };
}

async function joinAccount(
  request: Request,
  db: D1Database,
  tokenHash: string,
  now: number,
) {
  const body = await readJson(request, ["code", "recoveryCode", "deviceName"]);
  const hasCode = body.code !== undefined,
    hasRecovery = body.recoveryCode !== undefined;
  if (hasCode === hasRecovery) throw new SyncError("invalid_request");
  const raw = hasCode ? body.code : body.recoveryCode;
  if (typeof raw !== "string") throw new SyncError("invalid_request");
  const deviceName = parseName(body.deviceName, "invalid_device_name");
  const code = hasCode ? normalizePairingCode(raw) : normalizeRecoveryCode(raw);
  if (!code) throw new SyncError("invalid_code", 404);
  const codeHash = hasCode ? await pairingHash(code) : await recoveryHash(code);
  const target = hasCode
    ? await db
        .prepare(
          "SELECT account_id AS id FROM sync_pairings WHERE code_hash = ? AND expires_at > ?",
        )
        .bind(codeHash, now)
        .first<{ id: string }>()
    : await db
        .prepare("SELECT id FROM sync_accounts WHERE recovery_hash = ?")
        .bind(codeHash)
        .first<{ id: string }>();
  if (!target) throw new SyncError("invalid_code", 404);
  const result = async (row: Linked) => {
    if (row.account_id !== target.id)
      throw new SyncError("already_linked", 409);
    const data = await accountData(db, row.account_id);
    return { account: accountView(row), revision: data.revision };
  };
  const existing = await linked(db, tokenHash);
  // Already linked: a repeated join is harmless and leaves the code unused.
  if (existing) return result(existing);
  if (
    hasCode &&
    (await count(
      db,
      "SELECT COUNT(*) AS count FROM sync_devices WHERE account_id = ?",
      target.id,
    )) >= MAX_DEVICES
  )
    throw new SyncError("too_many_devices", 409);
  // One transaction: the device is only added while the code is still valid
  // and the account has room, and a pairing code is consumed only when the
  // device was added, so two devices can never redeem the same code.
  const statements = [
    orphanCleanup(db, tokenHash),
    // The recovery code must always get the owner back in: on a full account
    // it replaces the device that was used least recently (e.g. an old
    // installation that no longer exists). Pairing codes respect the limit.
    ...(hasCode
      ? []
      : [
          db
            .prepare(
              `DELETE FROM sync_devices WHERE id = (
                SELECT id FROM sync_devices WHERE account_id = ? ORDER BY last_seen ASC, created_at ASC LIMIT 1)
              AND (SELECT COUNT(*) FROM sync_devices WHERE account_id = ?) >= ?`,
            )
            .bind(target.id, target.id, MAX_DEVICES),
        ]),
    db
      .prepare(
        `INSERT OR IGNORE INTO sync_devices (id, account_id, token_hash, name, created_at, last_seen)
        SELECT ?, ?, ?, ?, ?, ?
        WHERE EXISTS (SELECT 1 FROM sync_accounts WHERE id = ?)
        AND (SELECT COUNT(*) FROM sync_devices WHERE account_id = ?) < ?
        AND (? = 0 OR EXISTS (
          SELECT 1 FROM sync_pairings WHERE code_hash = ? AND account_id = ? AND expires_at > ?))`,
      )
      .bind(
        randomHex(12),
        target.id,
        tokenHash,
        deviceName,
        now,
        now,
        target.id,
        target.id,
        MAX_DEVICES,
        hasCode ? 1 : 0,
        codeHash,
        target.id,
        now,
      ),
  ];
  if (hasCode)
    statements.push(
      db
        .prepare(
          `DELETE FROM sync_pairings WHERE code_hash = ? AND EXISTS (
            SELECT 1 FROM sync_devices WHERE token_hash = ? AND account_id = ?)`,
        )
        .bind(codeHash, tokenHash, target.id),
    );
  await db.batch(statements);
  const row = await linked(db, tokenHash);
  if (row) return result(row);
  if (
    (await count(
      db,
      "SELECT COUNT(*) AS count FROM sync_devices WHERE account_id = ?",
      target.id,
    )) >= MAX_DEVICES
  )
    throw new SyncError("too_many_devices", 409);
  throw new SyncError("invalid_code", 404);
}

async function createPairing(db: D1Database, account: Linked, now: number) {
  const expiresAt = now + PAIRING_TTL;
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = randomCode(PAIRING_LENGTH);
    // Only the newest code of an account stays valid; expired codes go too.
    const [, inserted] = await db.batch([
      db
        .prepare(
          "DELETE FROM sync_pairings WHERE account_id = ? OR expires_at <= ?",
        )
        .bind(account.account_id, now),
      db
        .prepare(
          "INSERT OR IGNORE INTO sync_pairings (code_hash, account_id, expires_at) VALUES (?, ?, ?)",
        )
        .bind(await pairingHash(code), account.account_id, expiresAt),
    ]);
    if (inserted.meta.changes) return { code: group(code), expiresAt };
  }
  throw new SyncError("unavailable", 503);
}

async function rotateRecovery(db: D1Database, account: Linked) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = randomCode(RECOVERY_LENGTH);
    const result = await db
      .prepare("UPDATE OR IGNORE sync_accounts SET recovery_hash = ? WHERE id = ?")
      .bind(await recoveryHash(code), account.account_id)
      .run();
    if (result.meta.changes) return { recoveryCode: group(code) };
  }
  throw new SyncError("unavailable", 503);
}

async function route(
  request: Request,
  env: SyncEnv,
  tokenHash: string,
  now: number,
): Promise<[unknown, number?]> {
  const db = env.DB;
  const method = request.method;
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const [, sub, id] = parts;
  const notAllowed = new SyncError("method_not_allowed", 405);

  if (parts.length === 1) {
    if (method === "GET") {
      const since = url.searchParams.get("since");
      if (since !== null && !/^(0|[1-9]\d{0,14})$/.test(since))
        throw new SyncError("invalid_request");
      const account = await requireLinked(db, tokenHash);
      await db
        .prepare("UPDATE sync_devices SET last_seen = ? WHERE token_hash = ?")
        .bind(now, tokenHash)
        .run();
      const row = await accountData(db, account.account_id);
      return [
        {
          account: accountView(account),
          revision: row.revision,
          updatedAt: row.updated_at,
          ...(since !== null && Number(since) === row.revision
            ? {}
            : { data: row.data }),
        },
      ];
    }
    if (method === "PUT") {
      const body = await readJson(request, ["baseRevision", "data"], MAX_SYNC_BODY);
      if (
        !Number.isSafeInteger(body.baseRevision) ||
        (body.baseRevision as number) < 0
      )
        throw new SyncError("invalid_request");
      const data = parseData(body.data);
      const account = await requireLinked(db, tokenHash);
      const [saved] = await db.batch([
        db
          .prepare(
            `UPDATE sync_accounts SET data = ?, revision = revision + 1, updated_at = ?
            WHERE id = ? AND revision = ?`,
          )
          .bind(data, now, account.account_id, body.baseRevision),
        db
          .prepare("UPDATE sync_devices SET last_seen = ? WHERE token_hash = ?")
          .bind(now, tokenHash),
      ]);
      const row = await accountData(db, account.account_id);
      if (!saved.meta.changes)
        return [
          {
            error: "conflict",
            revision: row.revision,
            updatedAt: row.updated_at,
            data: row.data,
          },
          409,
        ];
      return [{ revision: row.revision, updatedAt: row.updated_at }];
    }
    throw notAllowed;
  }
  if (parts.length === 2 && sub === "account") {
    if (method === "POST")
      return [await createAccount(request, db, tokenHash, now), 201];
    if (method === "PUT") {
      const body = await readJson(request, ["name"]);
      const name = parseName(body.name, "invalid_name");
      const account = await requireLinked(db, tokenHash);
      await db
        .prepare("UPDATE sync_accounts SET name = ? WHERE id = ?")
        .bind(name, account.account_id)
        .run();
      return [{ account: accountView({ ...account, account_name: name }) }];
    }
    if (method === "DELETE") {
      await discardBody(request);
      const account = await requireLinked(db, tokenHash);
      await db.batch([
        db
          .prepare("DELETE FROM sync_pairings WHERE account_id = ?")
          .bind(account.account_id),
        db
          .prepare("DELETE FROM sync_devices WHERE account_id = ?")
          .bind(account.account_id),
        db
          .prepare("DELETE FROM sync_accounts WHERE id = ?")
          .bind(account.account_id),
      ]);
      return [{ deleted: true }];
    }
    throw notAllowed;
  }
  if (parts.length === 2 && sub === "join") {
    if (method !== "POST") throw notAllowed;
    // Codes are guessable in principle, so joining is also limited per IP.
    if (
      !env.API_LIMIT ||
      !(
        await env.API_LIMIT.limit({
          key: await digest(request.headers.get("CF-Connecting-IP") ?? "unknown"),
        })
      ).success
    )
      throw new SyncError("rate_limited", 429);
    return [await joinAccount(request, db, tokenHash, now)];
  }
  if (parts.length === 2 && sub === "pair") {
    if (method !== "POST") throw notAllowed;
    await discardBody(request);
    const account = await requireLinked(db, tokenHash);
    return [await createPairing(db, account, now), 201];
  }
  if (parts.length === 2 && sub === "recovery") {
    if (method !== "POST") throw notAllowed;
    await discardBody(request);
    const account = await requireLinked(db, tokenHash);
    return [await rotateRecovery(db, account)];
  }
  if (parts.length === 2 && sub === "device") {
    if (method !== "PUT") throw notAllowed;
    const body = await readJson(request, ["name"]);
    const name = parseName(body.name, "invalid_device_name");
    const device = await db
      .prepare(
        "UPDATE sync_devices SET name = ? WHERE token_hash = ? RETURNING id, name, created_at, last_seen",
      )
      .bind(name, tokenHash)
      .first<{ id: string; name: string; created_at: number; last_seen: number }>();
    if (!device) throw new SyncError("not_linked", 404);
    return [
      {
        device: {
          id: device.id,
          name: device.name,
          createdAt: device.created_at,
          lastSeen: device.last_seen,
          me: true,
        },
      },
    ];
  }
  if (parts.length === 2 && sub === "devices") {
    if (method !== "GET") throw notAllowed;
    const account = await requireLinked(db, tokenHash);
    const rows = (
      await db
        .prepare(
          `SELECT id, name, created_at, last_seen, token_hash = ? AS me
          FROM sync_devices WHERE account_id = ? ORDER BY created_at, id`,
        )
        .bind(tokenHash, account.account_id)
        .all<{
          id: string;
          name: string;
          created_at: number;
          last_seen: number;
          me: number;
        }>()
    ).results;
    return [
      {
        devices: rows.map((row) => ({
          id: row.id,
          name: row.name,
          createdAt: row.created_at,
          lastSeen: row.last_seen,
          me: !!row.me,
        })),
      },
    ];
  }
  if (parts.length === 3 && sub === "devices") {
    if (method !== "DELETE") throw notAllowed;
    await discardBody(request);
    const account = await requireLinked(db, tokenHash);
    if (!deviceIdPattern.test(id)) throw new SyncError("device_not_found", 404);
    // Removing the last device keeps the account: the recovery code restores it.
    const result = await db
      .prepare("DELETE FROM sync_devices WHERE id = ? AND account_id = ?")
      .bind(id, account.account_id)
      .run();
    if (!result.meta.changes) throw new SyncError("device_not_found", 404);
    return [{ removed: true }];
  }
  throw new SyncError("not_found", 404);
}

export async function handleSync(
  request: Request,
  env: SyncEnv,
  headers: Headers,
  now = Date.now(),
) {
  const reply = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers });
  const origin = request.headers.get("Origin");
  // The native app sends no Origin; browsers must come from the app.
  if (origin !== null && origin !== env.APP_ORIGIN)
    return reply({ error: "origin_not_allowed" }, 403);
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  const token =
    request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (!tokenPattern.test(token)) return reply({ error: "unauthorized" }, 401);
  const tokenHash = await digest(token);
  if (
    !env.SYNC_LIMIT ||
    !(await env.SYNC_LIMIT.limit({ key: tokenHash })).success
  )
    return reply({ error: "rate_limited" }, 429);
  try {
    const [data, status] = await route(request, env, tokenHash, now);
    return reply(data, status);
  } catch (error) {
    if (error instanceof SyncError)
      return reply({ error: error.code }, error.status);
    return reply({ error: "unavailable" }, 503);
  }
}
