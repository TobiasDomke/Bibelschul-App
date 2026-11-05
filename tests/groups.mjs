import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { randomBytes } from "node:crypto";
import { build } from "esbuild";
import { readFile, mkdir } from "node:fs/promises";
await mkdir(".test-runtime", { recursive: true });
await build({
  entryPoints: ["worker/index.ts"],
  bundle: true,
  platform: "node",
  format: "esm",
  outfile: ".test-runtime/groups-worker.mjs",
});
const { handleRequest, digest } = await import(
  "../.test-runtime/groups-worker.mjs"
);

const db = new DatabaseSync(":memory:");
db.exec("PRAGMA foreign_keys = ON");
db.exec(await readFile("worker/migrations/0001_reminders.sql", "utf8"));
db.exec(await readFile("worker/migrations/0002_groups.sql", "utf8"));
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
const limited = [];
const env = {
  DB,
  API_LIMIT: {
    async limit() {
      return { success: true };
    },
  },
  GROUP_LIMIT: {
    async limit({ key }) {
      limited.push(key);
      return { success: true };
    },
  },
  APP_ORIGIN: "https://leseweg.pages.dev",
  VAPID_PUBLIC_KEY: "",
  VAPID_PRIVATE_KEY: "",
};
const newToken = () => randomBytes(32).toString("base64url");
const anna = newToken(),
  ben = newToken(),
  carl = newToken(),
  dora = newToken();
let clock = Date.parse("2026-11-05T10:00:00Z");
async function call(path, method = "GET", body, token = anna, options = {}) {
  const headers = { Authorization: "Bearer " + token };
  if (options.origin) headers.Origin = options.origin;
  if (body !== undefined)
    headers["Content-Type"] = options.contentType ?? "application/json";
  const response = await handleRequest(
    new Request("https://groups.example" + path, {
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
  return { status: response.status, data: text ? JSON.parse(text) : null };
}
const stats = (over = {}) => ({
  chapters: 120,
  total: 1189,
  weekChapters: 9,
  streak: 4,
  minutes: 600,
  wpm: 210,
  lastRead: "2026-11-04",
  plan: "Bibel in einem Jahr",
  ...over,
});
const rows = (sql, ...values) => db.prepare(sql).all(...values);

// Native app without Origin may create a group; the caller becomes owner.
let res = await call("/groups", "POST", {
  groupName: "  Klasse 2026  ",
  name: "Anna",
  stats: stats(),
  visible: true,
});
assert.equal(res.status, 201);
const group = res.data.group;
assert.equal(group.name, "Klasse 2026");
assert.match(group.code, /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$/);
assert.match(group.id, /^[0-9a-f]{32}$/);
assert.equal(group.owner, true);
assert.equal(group.hiddenCount, 0);
assert.equal(group.members.length, 1);
assert.deepEqual(group.members[0].stats, stats());
assert.equal(group.members[0].me, true);
assert.equal(group.members[0].owner, true);
assert.match(group.me.memberId, /^[0-9a-f]{24}$/);
const storedCode = rows("SELECT code FROM groups")[0].code;
assert.equal(storedCode, group.code.replace("-", ""), "Codes are stored without dash");
const stored = JSON.stringify(rows("SELECT * FROM members"));
assert(!stored.includes(anna), "Only the token hash is stored");
assert(stored.includes(await digest(anna)));
assert.equal(limited.at(-1), await digest(anna), "Rate limit keyed by token hash");

// App origin is allowed (with CORS), foreign origins are rejected.
res = await call("/groups", "GET", undefined, anna, { origin: env.APP_ORIGIN });
assert.equal(res.status, 200);
assert.equal(res.data.groups.length, 1);
assert.equal(
  (await call("/groups", "GET", undefined, anna, { origin: "https://evil.example" })).status,
  403,
);
const preflight = await handleRequest(
  new Request("https://groups.example/groups/join", {
    method: "OPTIONS",
    headers: { Origin: env.APP_ORIGIN },
  }),
  env,
);
assert.equal(preflight.status, 204);
assert.equal(preflight.headers.get("Access-Control-Allow-Origin"), env.APP_ORIGIN);
assert.equal((await call("/groups", "GET", undefined, "short")).status, 401);
// Existing reminder routes keep requiring the app origin.
assert.equal((await call("/subscription", "GET")).status, 403);

// Code normalisation: lowercase, spaces, URL forms.
const raw = group.code.replace("-", "");
res = await call("/groups/join", "POST", {
  code: " " + group.code.toLowerCase().replace("-", " ") + " ",
  name: "Ben",
  stats: stats({ chapters: 300 }),
}, ben);
assert.equal(res.status, 200);
assert.equal(res.data.group.id, group.id);
assert.equal(res.data.group.owner, false);
assert.equal(res.data.group.members.length, 2);
res = await call("/groups/join", "POST", {
  code: `https://leseweg.pages.dev/?join=1&code=${group.code}`,
  name: "Carl",
  stats: null,
  visible: false,
}, carl);
assert.equal(res.status, 200);
assert.equal(res.data.group.me.visible, false);
assert.equal(res.data.group.members.some((m) => m.me && m.name === "Carl"), true, "Hidden caller sees themself");
res = await call("/groups/join", "POST", {
  code: `leseweg://g/${raw.toLowerCase()}`,
  name: "Dora",
  stats: stats({ wpm: null, lastRead: null, plan: "" }),
}, dora);
assert.equal(res.status, 200);
assert.equal(res.data.group.members.length, 3);
for (const code of ["ABCD", "ABCD-EFG1", "ABCD-EFGO", 12345678, null])
  assert.equal(
    (await call("/groups/join", "POST", { code, name: "X" }, dora)).status,
    400,
    String(code),
  );
assert.equal(
  (await call("/groups/join", "POST", { code: "ZZZZ-ZZZZ", name: "X" }, dora)).status,
  404,
);

// Visibility: hidden members are counted, never shown.
res = await call("/groups/" + group.id, "GET", undefined, ben);
assert.equal(res.data.group.hiddenCount, 1);
assert.deepEqual(res.data.group.members.map((m) => m.name), ["Anna", "Ben", "Dora"]);
assert(!JSON.stringify(res.data).includes("Carl"));
res = await call("/groups/" + group.id + "/me", "PUT", { visible: false }, ben);
assert.equal(res.status, 200);
assert.equal(res.data.group.me.visible, false);
assert.deepEqual(res.data.group.members.find((m) => m.me).stats.chapters, 300, "Hidden caller still sees own stats");
res = await call("/groups/" + group.id, "GET", undefined, anna);
assert.equal(res.data.group.hiddenCount, 2);
assert(!JSON.stringify(res.data).includes("Ben"));
assert(!JSON.stringify(res.data).includes("300"));
assert.equal((await call("/groups/" + group.id + "/me", "PUT", { visible: "no" }, ben)).status, 400);
assert.equal((await call("/groups/" + group.id + "/me", "PUT", { visible: true, x: 1 }, ben)).status, 400);
await call("/groups/" + group.id + "/me", "PUT", { visible: true }, ben);

// Rejoining refreshes the membership instead of duplicating it.
res = await call("/groups/join", "POST", { code: group.code, name: "Benjamin" }, ben);
assert.equal(res.status, 200);
assert.equal(res.data.group.members.length, 3);
assert.equal(res.data.group.me.name, "Benjamin");
assert.equal(res.data.group.members.find((m) => m.me).stats.chapters, 300, "Omitted stats are kept");

// PUT /me fans out to every membership.
res = await call("/groups", "POST", { groupName: "Freunde", name: "Anna" });
const second = res.data.group;
assert.equal(second.members[0].stats, null);
res = await call("/me", "PUT", { name: "Anna B.", stats: stats({ chapters: 500 }) });
assert.deepEqual(res.data, { updated: 2 });
for (const id of [group.id, second.id]) {
  res = await call("/groups/" + id);
  assert.equal(res.data.group.me.name, "Anna B.");
  assert.equal(res.data.group.members.find((m) => m.me).stats.chapters, 500);
}
assert.equal((await call("/me", "PUT", { name: "Anna" })).status, 400, "stats is required");
res = await call("/groups");
assert.deepEqual(
  res.data.groups.map((g) => [g.name, g.memberCount, g.owner]),
  [["Klasse 2026", 4, true], ["Freunde", 1, true]],
);

// Input validation.
const bad = [
  { chapters: 1.5 },
  { chapters: -1 },
  { chapters: 2001, total: 2000 },
  { chapters: 20, total: 10 },
  { total: 0 },
  { weekChapters: 2001 },
  { streak: 10001 },
  { minutes: 1000001 },
  { wpm: 2001 },
  { wpm: "200" },
  { lastRead: "2026-02-30" },
  { lastRead: "05.11.2026" },
  { plan: "x".repeat(61) },
  { plan: "a\u0000b" },
  { plan: null },
  { extra: 1 },
];
for (const over of bad)
  assert.equal((await call("/me", "PUT", { name: "A", stats: stats(over) })).status, 400, JSON.stringify(over));
const missing = stats();
delete missing.plan;
assert.equal((await call("/me", "PUT", { name: "A", stats: missing })).status, 400);
assert.equal((await call("/me", "PUT", { name: "A", stats: [] })).status, 400);
assert.equal((await call("/me", "PUT", { name: "A", stats: stats(), extra: 1 })).data.error, "invalid_request");
for (const name of ["", "   ", "x".repeat(41), "a\nb", "a‮b", 7])
  assert.equal((await call("/me", "PUT", { name, stats: null })).status, 400, JSON.stringify(name));
assert.equal((await call("/me", "PUT", { name: "😀".repeat(40), stats: null }, dora)).status, 200);
assert.equal((await call("/groups", "POST", { groupName: "g".repeat(61), name: "A" })).data.error, "invalid_group_name");
assert.equal((await call("/me", "PUT", "{", anna)).status, 400);
assert.equal((await call("/me", "PUT", { name: "A", stats: null }, anna, { contentType: "text/plain" })).status, 415);
assert.equal((await call("/me", "PUT", { name: "A", stats: null, pad: "x".repeat(5000) })).status, 413);

// Owner-only actions.
const benId = (await call("/groups/" + group.id, "GET", undefined, ben)).data.group.me.memberId;
const doraId = (await call("/groups/" + group.id, "GET", undefined, dora)).data.group.me.memberId;
assert.equal((await call(`/groups/${group.id}/members/${doraId}`, "DELETE", undefined, ben)).data.error, "forbidden");
assert.equal((await call(`/groups/${group.id}/code`, "POST", undefined, ben)).status, 403);
assert.equal((await call(`/groups/${group.id}/members/${group.me.memberId}`, "DELETE")).status, 400);
assert.equal((await call(`/groups/${group.id}/members/${"0".repeat(24)}`, "DELETE")).status, 404);
res = await call(`/groups/${group.id}/members/${doraId}`, "DELETE");
assert.equal(res.status, 200);
assert.equal(res.data.group.members.some((m) => m.memberId === doraId), false);
assert.equal((await call("/groups/" + group.id, "GET", undefined, dora)).status, 404);
res = await call(`/groups/${group.id}/code`, "POST");
assert.equal(res.status, 200);
assert.notEqual(res.data.group.code, group.code);
const newCode = res.data.group.code;
assert.equal((await call("/groups/join", "POST", { code: group.code, name: "Dora" }, dora)).status, 404, "Old code stops working");
assert.equal((await call("/groups/join", "POST", { code: newCode, name: "Dora" }, dora)).status, 200);

// Non-members see nothing.
const outsider = newToken();
assert.equal((await call("/groups/" + group.id, "GET", undefined, outsider)).data.error, "group_not_found");
assert.equal((await call("/groups/" + group.id + "/me", "PUT", { visible: false }, outsider)).status, 404);
assert.equal((await call("/groups/" + group.id + "/me", "DELETE", undefined, outsider)).status, 404);
assert.equal((await call("/groups/not-an-id", "GET", undefined, outsider)).status, 404);
assert.equal((await call("/groups/" + group.id, "DELETE")).status, 405);
assert.equal((await call("/groups/" + group.id + "/nope", "GET")).status, 404);

// Leaving: oldest remaining member becomes owner, empty groups disappear.
res = await call("/groups/" + group.id + "/me", "DELETE");
assert.deepEqual(res.data, { left: true });
res = await call("/groups/" + group.id, "GET", undefined, ben);
assert.equal(res.data.group.owner, true, "Ben joined first after Anna");
assert.equal((await call("/groups/" + group.id, "GET", undefined, carl)).data.group.owner, false);
assert.equal((await call("/groups/" + group.id, "GET")).status, 404);
await call("/groups/" + second.id + "/me", "DELETE");
assert.equal(rows("SELECT * FROM groups WHERE id = ?", second.id).length, 0, "Empty group deleted");
assert.equal(rows("SELECT * FROM members WHERE group_id = ?", second.id).length, 0);

// DELETE /me removes every membership with the same rules.
res = await call("/groups", "POST", { groupName: "Ben allein", name: "Ben" }, ben);
const solo = res.data.group.id;
res = await call("/me", "DELETE", undefined, ben);
assert.deepEqual(res.data, { deleted: 2 });
assert.equal(rows("SELECT * FROM groups WHERE id = ?", solo).length, 0);
assert.equal((await call("/groups/" + group.id, "GET", undefined, carl)).data.group.owner, true, "Carl inherits ownership");
assert.deepEqual((await call("/groups", "GET", undefined, ben)).data, { groups: [] });
assert.deepEqual((await call("/me", "DELETE", undefined, ben)).data, { deleted: 0 });

// Limits.
const busy = newToken();
for (let i = 0; i < 20; i++)
  assert.equal((await call("/groups", "POST", { groupName: "G" + i, name: "Busy" }, busy)).status, 201);
assert.equal((await call("/groups", "POST", { groupName: "G21", name: "Busy" }, busy)).data.error, "too_many_groups");
assert.equal((await call("/groups/join", "POST", { code: newCode, name: "Busy" }, busy)).data.error, "too_many_groups");
await call("/me", "DELETE", undefined, busy);
const now = Date.now();
const fill = db.prepare(
  "INSERT INTO members (group_id, member_id, token_hash, name, joined_at, updated_at) VALUES (?, ?, ?, 'F', ?, ?)",
);
const current = rows("SELECT COUNT(*) AS n FROM members WHERE group_id = ?", group.id)[0].n;
for (let i = current; i < 200; i++)
  fill.run(group.id, randomBytes(12).toString("hex"), "fill" + i, now, now);
assert.equal((await call("/groups/join", "POST", { code: newCode, name: "Late" }, newToken())).data.error, "group_full");
const fillGroup = db.prepare("INSERT INTO groups (id, code, name, created_at) VALUES (?, ?, 'F', ?)");
const total = rows("SELECT COUNT(*) AS n FROM groups")[0].n;
for (let i = total; i < 5000; i++)
  fillGroup.run(randomBytes(16).toString("hex"), "F" + String(i).padStart(7, "0"), now);
res = await call("/groups", "POST", { groupName: "Zu viel", name: "X" }, newToken());
assert.equal(res.status, 503);
assert.equal(res.data.error, "capacity_reached");

// Rate limiting: binding missing or exhausted.
assert.equal((await call("/groups", "GET", undefined, anna, { env: { ...env, GROUP_LIMIT: undefined } })).status, 429);
assert.equal(
  (
    await call("/groups", "GET", undefined, anna, {
      env: { ...env, GROUP_LIMIT: { limit: async () => ({ success: false }) } },
    })
  ).data.error,
  "rate_limited",
);

db.close();
console.log(
  "Groups: create/join/codes, URL normalisation, visibility privacy, profile fan-out, validation, ownership, leaving, limits, origin and rate limits passed.",
);
