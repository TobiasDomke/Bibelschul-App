import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { randomBytes } from "node:crypto";
import { build } from "esbuild";
import { readFile, readdir, mkdir } from "node:fs/promises";
await mkdir(".test-runtime", { recursive: true });
await build({
  entryPoints: ["worker/index.ts"],
  bundle: true,
  platform: "node",
  format: "esm",
  outfile: ".test-runtime/sync-worker.mjs",
});
const { handleRequest, digest } = await import(
  "../.test-runtime/sync-worker.mjs"
);

const db = new DatabaseSync(":memory:");
db.exec("PRAGMA foreign_keys = ON");
for (const file of (await readdir("worker/migrations")).filter((f) => f.endsWith(".sql")).sort())
  db.exec(await readFile("worker/migrations/" + file, "utf8"));
const DB = {
  prepare(sql) {
    let values = [];
    const query = {
      bind(...args) {
        values = args;
        return query;
      },
      async all() {
        return { results: db.prepare(sql).all(...values) };
      },
      async first() {
        return db.prepare(sql).get(...values) ?? null;
      },
      async run() {
        return { meta: db.prepare(sql).run(...values) };
      },
      runSync() {
        return { meta: db.prepare(sql).run(...values) };
      },
    };
    return query;
  },
  // D1 runs a batch as one transaction.
  async batch(statements) {
    db.exec("BEGIN");
    try {
      const results = statements.map((statement) => statement.runSync());
      db.exec("COMMIT");
      return results;
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  },
};
const syncKeys = [],
  apiKeys = [];
const env = {
  DB,
  API_LIMIT: {
    async limit({ key }) {
      apiKeys.push(key);
      return { success: true };
    },
  },
  GROUP_LIMIT: {
    async limit() {
      return { success: true };
    },
  },
  SYNC_LIMIT: {
    async limit({ key }) {
      syncKeys.push(key);
      return { success: true };
    },
  },
  APP_ORIGIN: "https://leseweg.pages.dev",
  VAPID_PUBLIC_KEY: "",
  VAPID_PRIVATE_KEY: "",
};
const newToken = () => randomBytes(32).toString("base64url");
const phone = newToken(),
  tablet = newToken(),
  laptop = newToken(),
  stranger = newToken();
let clock = Date.parse("2026-11-06T10:00:00Z");
async function call(path, method = "GET", body, token = phone, options = {}) {
  const headers = { Authorization: "Bearer " + token };
  if (options.origin) headers.Origin = options.origin;
  if (options.ip) headers["CF-Connecting-IP"] = options.ip;
  if (body !== undefined)
    headers["Content-Type"] = options.contentType ?? "application/json";
  const response = await handleRequest(
    new Request("https://sync.example" + path, {
      method,
      headers,
      body:
        body === undefined
          ? undefined
          : typeof body === "string"
            ? body
            : JSON.stringify(body),
    }),
    options.env ?? env,
    undefined,
    (clock += 1000),
  );
  const text = await response.text();
  return {
    status: response.status,
    data: text ? JSON.parse(text) : null,
    headers: response.headers,
  };
}
const rows = (sql, ...values) => db.prepare(sql).all(...values);
const CODE = "[ABCDEFGHJKMNPQRSTUVWXYZ23456789]";
const recoveryFormat = new RegExp(`^${CODE}{4}(-${CODE}{4}){5}$`);
const pairingFormat = new RegExp(`^${CODE}{4}-${CODE}{4}$`);
const doc = (over = {}) => JSON.stringify({ plans: [], notes: { a: 1 }, ...over });

// Not linked yet.
let res = await call("/sync");
assert.equal(res.status, 404);
assert.equal(res.data.error, "not_linked");
assert.equal((await call("/sync/devices")).data.error, "not_linked");
assert.equal((await call("/sync/pair", "POST")).data.error, "not_linked");

// Create an account (native app without Origin).
res = await call("/sync/account", "POST", { name: "  Tobias  ", deviceName: "iPhone" });
assert.equal(res.status, 201);
const account = res.data.account;
const recoveryCode = res.data.recoveryCode;
assert.match(recoveryCode, recoveryFormat);
assert.match(account.id, /^[0-9a-f]{32}$/);
assert.match(account.deviceId, /^[0-9a-f]{24}$/);
assert.deepEqual(
  { ...account, id: undefined, deviceId: undefined },
  { id: undefined, deviceId: undefined, name: "Tobias", deviceName: "iPhone", createdAt: clock, devices: 1 },
);
const stored = JSON.stringify([rows("SELECT * FROM sync_accounts"), rows("SELECT * FROM sync_devices")]);
assert(!stored.includes(phone), "Only the token hash is stored");
assert(stored.includes(await digest(phone)));
assert(!stored.includes(recoveryCode.replace(/-/g, "")), "Only the recovery hash is stored");
assert.equal(syncKeys.at(-1), await digest(phone), "SYNC_LIMIT keyed by token hash");
assert.equal(
  (await call("/sync/account", "POST", { name: "Zweites", deviceName: "iPhone" })).data.error,
  "already_linked",
);

// GET before the first upload.
res = await call("/sync");
assert.equal(res.status, 200);
assert.equal(res.data.revision, 0);
assert.equal(res.data.data, null);
assert.equal(res.data.account.id, account.id);
assert.equal(typeof res.data.updatedAt, "number");
res = await call("/sync?since=0");
assert.equal("data" in res.data, false, "since=revision omits data");
assert.equal(rows("SELECT last_seen FROM sync_devices")[0].last_seen, clock, "GET updates last_seen");
assert.equal((await call("/sync?since=abc")).status, 400);
assert.equal((await call("/sync?since=-1")).status, 400);

// Upload, then read.
res = await call("/sync", "PUT", { baseRevision: 0, data: doc() });
assert.equal(res.status, 200);
assert.deepEqual(res.data, { revision: 1, updatedAt: clock });
res = await call("/sync");
assert.equal(res.data.revision, 1);
assert.equal(res.data.data, doc());
assert.equal("data" in (await call("/sync?since=1")).data, false);
assert.equal((await call("/sync?since=0")).data.data, doc(), "Older since returns data");

// Conflict returns the current document.
res = await call("/sync", "PUT", { baseRevision: 0, data: doc({ stale: true }) });
assert.equal(res.status, 409);
assert.equal(res.data.error, "conflict");
assert.equal(res.data.revision, 1);
assert.equal(res.data.data, doc());
assert.equal(typeof res.data.updatedAt, "number");
res = await call("/sync", "PUT", { baseRevision: 1, data: doc({ second: true }) });
assert.equal(res.data.revision, 2);

// Data validation.
for (const data of ["[]", "1", "null", '"x"', "{", "", "{}x", 5, null, { a: 1 }])
  assert.equal(
    (await call("/sync", "PUT", { baseRevision: 2, data })).data.error,
    "invalid_data",
    JSON.stringify(data),
  );
assert.equal((await call("/sync", "PUT", { baseRevision: 2, data: "{}" })).status, 200, "Minimum 2 bytes");
for (const baseRevision of [-1, 1.5, "3", null, undefined])
  assert.equal(
    (await call("/sync", "PUT", { baseRevision, data: "{}" })).data.error,
    "invalid_request",
    String(baseRevision),
  );
const big = JSON.stringify({ blob: "x".repeat(1_000_000 - 11) });
assert.equal(new TextEncoder().encode(big).length, 1_000_000);
res = await call("/sync", "PUT", { baseRevision: 3, data: big });
assert.equal(res.status, 200, "Exactly 1,000,000 bytes is accepted");
assert.equal(res.data.revision, 4);
res = await call("/sync", "PUT", { baseRevision: 4, data: JSON.stringify({ blob: "x".repeat(1_000_000 - 10) }) });
assert.equal(res.status, 413);
assert.equal(res.data.error, "too_large");
// Multi-byte characters count as UTF-8 bytes.
res = await call("/sync", "PUT", { baseRevision: 4, data: JSON.stringify({ t: "ä".repeat(500_000) }) });
assert.equal(res.status, 413);
assert.equal(
  (await call("/sync", "PUT", JSON.stringify({ baseRevision: 4, data: "{}", pad: "x".repeat(1_100_001) }))).status,
  413,
  "Body limit",
);
assert.equal((await call("/sync", "PUT", { baseRevision: 4, data: "{}", extra: 1 })).data.error, "invalid_request");
assert.equal((await call("/sync", "PUT", "{", phone)).data.error, "invalid_request");
assert.equal((await call("/sync", "PUT", { baseRevision: 4, data: "{}" }, phone, { contentType: "text/plain" })).status, 415);
res = await call("/sync", "PUT", { baseRevision: 4, data: doc({ final: 1 }) });
assert.equal(res.data.revision, 5);

// Pairing: a second device joins and sees the same data.
res = await call("/sync/pair", "POST");
assert.equal(res.status, 201);
assert.match(res.data.code, pairingFormat);
assert.equal(res.data.expiresAt, clock + 10 * 60 * 1000);
const pairing = res.data.code;
assert.equal(rows("SELECT * FROM sync_pairings").length, 1);
assert(!JSON.stringify(rows("SELECT * FROM sync_pairings")).includes(pairing.replace("-", "")));
res = await call("/sync/join", "POST", { code: pairing.toLowerCase().replace("-", " "), deviceName: "iPad" }, tablet, { ip: "203.0.113.7" });
assert.equal(res.status, 200);
assert.equal(res.data.account.id, account.id);
assert.equal(res.data.account.deviceName, "iPad");
assert.equal(res.data.account.devices, 2);
assert.equal(res.data.revision, 5);
assert.notEqual(res.data.account.deviceId, account.deviceId);
assert.equal(apiKeys.at(-1), await digest("203.0.113.7"), "Join is limited by IP hash");
assert.equal((await call("/sync", "GET", undefined, tablet)).data.data, doc({ final: 1 }));
assert.equal(rows("SELECT * FROM sync_pairings").length, 0, "Code consumed");
// Single use.
assert.equal(
  (await call("/sync/join", "POST", { code: pairing, deviceName: "Laptop" }, laptop)).data.error,
  "invalid_code",
);
// Repeated join by an already linked device of the same account simply returns.
res = await call("/sync/join", "POST", { code: pairing, deviceName: "iPad" }, tablet);
assert.equal(res.data.error, "invalid_code", "A used code stays invalid even for members");
res = await call("/sync/pair", "POST", undefined, tablet);
const pairing2 = res.data.code;
res = await call("/sync/join", "POST", { code: pairing2, deviceName: "iPad" }, tablet);
assert.equal(res.status, 200, "Same account: just returns");
assert.equal(res.data.account.devices, 2);
assert.equal(rows("SELECT * FROM sync_pairings").length, 1, "Not consumed by an already linked device");
// URL forms.
res = await call("/sync/join", "POST", { code: `https://leseweg.pages.dev/#verbinden=${pairing2}`, deviceName: "Laptop" }, laptop);
assert.equal(res.status, 200);
assert.equal(res.data.account.devices, 3);
res = await call("/sync/pair", "POST");
const pairing3 = res.data.code;
// A newer code replaces older codes of the account.
res = await call("/sync/pair", "POST");
const pairing4 = res.data.code;
assert.equal(rows("SELECT * FROM sync_pairings").length, 1);
const extra = newToken();
assert.equal((await call("/sync/join", "POST", { code: pairing3, deviceName: "Alt" }, extra)).data.error, "invalid_code");
res = await call("/sync/join", "POST", { code: `leseweg://sync?code=${pairing4.toLowerCase()}`, deviceName: "Neu" }, extra);
assert.equal(res.status, 200);
assert.equal((await call(`/sync/devices/${res.data.account.deviceId}`, "DELETE", undefined, extra)).data.removed, true);
// Expired codes are rejected and removed with the next code.
res = await call("/sync/pair", "POST");
const expiring = res.data.code;
clock += 10 * 60 * 1000;
assert.equal((await call("/sync/join", "POST", { code: expiring, deviceName: "Spät" }, stranger)).data.error, "invalid_code");
await call("/sync/pair", "POST", undefined, tablet);
assert.equal(rows("SELECT * FROM sync_pairings WHERE expires_at <= ?", clock).length, 0);
// Malformed codes and requests.
for (const code of ["ABCD", "ABCD-EFG1", "ABCD-EFGO", "ZZZZ-ZZZZ"])
  assert.equal((await call("/sync/join", "POST", { code, deviceName: "X" }, stranger)).data.error, "invalid_code", code);
for (const body of [
  { deviceName: "X" },
  { code: pairing, recoveryCode: recoveryCode, deviceName: "X" },
  { code: 12345678, deviceName: "X" },
  { code: pairing, deviceName: "X", extra: 1 },
])
  assert.equal((await call("/sync/join", "POST", body, stranger)).data.error, "invalid_request", JSON.stringify(body));
assert.equal((await call("/sync/join", "POST", { code: pairing, deviceName: "" }, stranger)).data.error, "invalid_device_name");
assert.equal((await call("/sync/join", "GET", undefined, stranger)).status, 405);
assert.equal((await call("/sync", "GET", undefined, stranger)).status, 404, "Failed joins link nothing");

// Already linked to another account.
const other = newToken();
await call("/sync/account", "POST", { name: "Andere", deviceName: "Handy" }, other);
res = await call("/sync/pair", "POST");
assert.equal(
  (await call("/sync/join", "POST", { code: res.data.code, deviceName: "Handy" }, other)).data.error,
  "already_linked",
);
assert.equal(rows("SELECT * FROM sync_pairings WHERE account_id = ?", account.id).length, 1, "Code survives");
assert.equal(
  (await call("/sync/join", "POST", { recoveryCode, deviceName: "Handy" }, other)).data.error,
  "already_linked",
);

// Devices: list, rename, remove.
res = await call("/sync/devices", "GET", undefined, tablet);
assert.deepEqual(res.data.devices.map((d) => [d.name, d.me]), [["iPhone", false], ["iPad", true], ["Laptop", false]]);
assert.deepEqual(Object.keys(res.data.devices[0]).sort(), ["createdAt", "id", "lastSeen", "me", "name"]);
const [phoneDevice, tabletDevice, laptopDevice] = res.data.devices;
assert(phoneDevice.createdAt < tabletDevice.createdAt && tabletDevice.createdAt < laptopDevice.createdAt);
res = await call("/sync/device", "PUT", { name: " iPad Pro " }, tablet);
assert.equal(res.status, 200);
assert.deepEqual(res.data.device, { ...tabletDevice, name: "iPad Pro" });
for (const name of ["", "   ", "x".repeat(41), "a\nb", "a" + String.fromCharCode(0x202e) + "b", "a" + String.fromCharCode(0x2028) + "b", 7])
  assert.equal((await call("/sync/device", "PUT", { name }, tablet)).data.error, "invalid_device_name", JSON.stringify(name));
assert.equal((await call("/sync/device", "PUT", { name: "😀".repeat(40) }, tablet)).status, 200, "40 code points");
assert.equal((await call("/sync/device", "PUT", { name: "iPad", x: 1 }, tablet)).data.error, "invalid_request");
await call("/sync/device", "PUT", { name: "iPad" }, tablet);
assert.equal((await call("/sync/device", "PUT", { name: "X" }, stranger)).data.error, "not_linked");
// Foreign or unknown ids.
const otherDevice = (await call("/sync/devices", "GET", undefined, other)).data.devices[0].id;
assert.equal((await call(`/sync/devices/${otherDevice}`, "DELETE")).data.error, "device_not_found");
assert.equal((await call(`/sync/devices/${"0".repeat(24)}`, "DELETE")).status, 404);
assert.equal((await call("/sync/devices/nope", "DELETE")).data.error, "device_not_found");
assert.equal((await call(`/sync/devices/${laptopDevice.id}`, "GET")).status, 405);
res = await call(`/sync/devices/${laptopDevice.id}`, "DELETE", undefined, tablet);
assert.deepEqual(res.data, { removed: true });
assert.equal((await call("/sync", "GET", undefined, laptop)).data.error, "not_linked");
assert.equal((await call("/sync")).data.account.devices, 2);

// Account rename.
res = await call("/sync/account", "PUT", { name: "Tobias B." }, tablet);
assert.equal(res.status, 200);
assert.equal(res.data.account.name, "Tobias B.");
assert.equal(res.data.account.deviceName, "iPad");
assert.equal((await call("/sync")).data.account.name, "Tobias B.");
assert.equal((await call("/sync/account", "PUT", { name: "" })).data.error, "invalid_name");
assert.equal((await call("/sync/account", "POST", { name: "X", deviceName: "Y" }, newToken())).status, 201);
assert.equal((await call("/sync/account", "POST", { name: "X" }, newToken())).data.error, "invalid_device_name");

// Recovery: self-remove both devices, the account survives and is restored.
res = await call(`/sync/devices/${tabletDevice.id}`, "DELETE", undefined, tablet);
assert.deepEqual(res.data, { removed: true }, "Removing yourself signs out");
assert.equal((await call("/sync", "GET", undefined, tablet)).data.error, "not_linked");
await call(`/sync/devices/${phoneDevice.id}`, "DELETE");
assert.equal(rows("SELECT * FROM sync_devices WHERE account_id = ?", account.id).length, 0);
assert.equal(rows("SELECT * FROM sync_accounts WHERE id = ?", account.id).length, 1, "Account kept without devices");
const restored = newToken();
res = await call("/sync/join", "POST", { recoveryCode: recoveryCode.toLowerCase().replace(/-/g, " "), deviceName: "Neues iPhone" }, restored);
assert.equal(res.status, 200);
assert.equal(res.data.account.id, account.id);
assert.equal(res.data.revision, 5);
assert.equal((await call("/sync", "GET", undefined, restored)).data.data, doc({ final: 1 }));
res = await call("/sync/join", "POST", { recoveryCode, deviceName: "Neues iPhone" }, restored);
assert.equal(res.status, 200, "Repeated recovery join returns");
assert.equal(res.data.account.devices, 1);
assert.equal((await call("/sync/join", "POST", { recoveryCode: "A".repeat(24), deviceName: "X" }, stranger)).data.error, "invalid_code");
assert.equal((await call("/sync/join", "POST", { recoveryCode: "ABCD-EFGH", deviceName: "X" }, stranger)).data.error, "invalid_code");
// Rotation: the old recovery code stops working.
res = await call("/sync/recovery", "POST", undefined, restored);
assert.equal(res.status, 200);
assert.match(res.data.recoveryCode, recoveryFormat);
assert.notEqual(res.data.recoveryCode, recoveryCode);
const rotated = res.data.recoveryCode;
assert.equal((await call("/sync/join", "POST", { recoveryCode, deviceName: "X" }, stranger)).data.error, "invalid_code");
res = await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "iPad" }, tablet);
assert.equal(res.status, 200);
assert.equal(res.data.account.devices, 2);

// Device limit.
const fillers = [];
for (let i = 2; i < 10; i++) {
  const token = newToken();
  fillers.push(token);
  assert.equal((await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "Gerät " + i }, token)).status, 200);
}
assert.equal((await call("/sync", "GET", undefined, restored)).data.account.devices, 10);
res = await call("/sync/pair", "POST", undefined, restored);
assert.equal(
  (await call("/sync/join", "POST", { code: res.data.code, deviceName: "Elf" }, stranger)).data.error,
  "too_many_devices",
);
assert.equal(rows("SELECT * FROM sync_pairings WHERE account_id = ?", account.id).length, 1, "Code kept when full");
// The recovery code still works on a full account: the least recently used
// device makes room, the count stays at the limit.
const before = rows("SELECT id, last_seen FROM sync_devices WHERE account_id = ? ORDER BY last_seen, created_at", account.id);
res = await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "Elf" }, stranger);
assert.equal(res.status, 200);
assert.equal(res.data.account.devices, 10);
assert.equal(rows("SELECT * FROM sync_devices WHERE id = ?", before[0].id).length, 0, "oldest device replaced");

// Transport: origin, CORS, auth, rate limits.
assert.equal((await call("/sync", "GET", undefined, restored, { origin: env.APP_ORIGIN })).status, 200);
res = await call("/sync", "GET", undefined, restored, { origin: "https://evil.example" });
assert.equal(res.status, 403);
assert.equal(res.data.error, "origin_not_allowed");
for (const path of ["/sync", "/sync/join", "/sync/devices/abc"]) {
  const preflight = await handleRequest(
    new Request("https://sync.example" + path, { method: "OPTIONS", headers: { Origin: env.APP_ORIGIN } }),
    env,
  );
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("Access-Control-Allow-Origin"), env.APP_ORIGIN);
  for (const m of ["GET", "PUT", "POST", "DELETE"])
    assert(preflight.headers.get("Access-Control-Allow-Methods").includes(m));
  assert(preflight.headers.get("Access-Control-Allow-Headers").includes("Authorization"));
}
assert.equal((await call("/sync", "GET", undefined, "short")).data.error, "unauthorized");
assert.equal((await call("/sync", "GET", undefined, "x".repeat(44))).status, 401);
assert.equal((await call("/sync", "GET", undefined, restored, { env: { ...env, SYNC_LIMIT: undefined } })).status, 429);
res = await call("/sync", "GET", undefined, restored, {
  env: { ...env, SYNC_LIMIT: { limit: async () => ({ success: false }) } },
});
assert.equal(res.status, 429);
assert.equal(res.data.error, "rate_limited");
const ipLimited = { ...env, API_LIMIT: { limit: async () => ({ success: false }) } };
res = await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "X" }, newToken(), { env: ipLimited });
assert.equal(res.status, 429);
assert.equal(res.data.error, "rate_limited");
assert.equal(
  (await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "X" }, newToken(), { env: { ...env, API_LIMIT: undefined } })).status,
  429,
);
assert.equal((await call("/sync", "GET", undefined, restored, { env: ipLimited })).status, 200, "IP limit only on join");
assert.equal((await call("/sync/nope", "GET", undefined, restored)).status, 404);
assert.equal((await call("/sync", "DELETE", undefined, restored)).status, 405);
assert.equal((await call("/sync/account", "PUT", { name: "x".repeat(5000) }, restored)).status, 413, "4096 byte body limit");
assert.equal((await call("/sync/pair", "POST", "x".repeat(5000), restored)).status, 413);
// Database failure.
const broken = { ...env, DB: { prepare() { throw new Error("down"); } } };
res = await call("/sync", "GET", undefined, restored, { env: broken });
assert.equal(res.status, 503);
assert.equal(res.data.error, "unavailable");

// Deleting the account removes devices, pairings and data.
res = await call("/sync/account", "DELETE", undefined, restored);
assert.deepEqual(res.data, { deleted: true });
assert.equal(rows("SELECT * FROM sync_accounts WHERE id = ?", account.id).length, 0);
assert.equal(rows("SELECT * FROM sync_devices WHERE account_id = ?", account.id).length, 0);
assert.equal(rows("SELECT * FROM sync_pairings WHERE account_id = ?", account.id).length, 0);
for (const token of [restored, tablet, ...fillers])
  assert.equal((await call("/sync", "GET", undefined, token)).data.error, "not_linked");
assert.equal((await call("/sync/join", "POST", { recoveryCode: rotated, deviceName: "X" }, stranger)).data.error, "invalid_code");
assert.equal((await call("/sync", "GET", undefined, other)).status, 200, "Other accounts untouched");
// A former device can start a new account.
assert.equal((await call("/sync/account", "POST", { name: "Neu", deviceName: "iPad" }, tablet)).status, 201);

// Capacity.
const fill = db.prepare(
  "INSERT INTO sync_accounts (id, name, recovery_hash, updated_at, created_at) VALUES (?, 'F', ?, 0, 0)",
);
db.exec("BEGIN");
for (let i = rows("SELECT COUNT(*) AS n FROM sync_accounts")[0].n; i < 20000; i++)
  fill.run(randomBytes(16).toString("hex"), "fill" + i);
db.exec("COMMIT");
res = await call("/sync/account", "POST", { name: "Zu viel", deviceName: "X" }, newToken());
assert.equal(res.status, 503);
assert.equal(res.data.error, "capacity_reached");

// Groups and reminder routes are unaffected.
res = await call("/groups", "POST", { groupName: "Klasse", name: "Anna" }, newToken());
assert.equal(res.status, 201);
assert.equal((await call("/subscription", "GET")).status, 403, "Reminders still require the app origin");
assert.equal((await call("/config", "GET")).data.available, false);

db.close();
console.log(
  "Sync: accounts, upload/conflict, since, pairing/recovery codes, devices, limits, validation, origin and rate limits passed.",
);
