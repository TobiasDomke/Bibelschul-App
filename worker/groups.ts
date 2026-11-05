import type {
  D1Database,
  D1PreparedStatement,
} from "@cloudflare/workers-types";
import { digest, readLimitedText, tokenPattern, type Env } from "./index";

// Reading groups ("Lesegruppen"): compare aggregate reading statistics with a
// class or friends. No accounts: a member is identified by the hash of the
// installation token. Only aggregates are stored, hidden members stay hidden,
// and leaving removes the member's row.

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 8;
const codePattern = new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`);
const groupIdPattern = /^[0-9a-f]{32}$/;
const memberIdPattern = /^[0-9a-f]{24}$/;
export const MAX_MEMBERS = 200;
export const MAX_GROUPS_PER_TOKEN = 20;
export const MAX_GROUPS = 5000;
const STAT_KEYS = [
  "chapters",
  "total",
  "weekChapters",
  "streak",
  "minutes",
  "wpm",
  "lastRead",
  "plan",
] as const;
/** Optional: share of the plan's text read, in hundredths of a percent (by words). */
const OPTIONAL_STAT_KEYS = ["progress"] as const;
// C0/C1 controls, line/paragraph separators and bidi overrides/isolates.
const controlPattern = /[\p{Cc}\u2028\u2029\u202A-\u202E\u2066-\u2069]/u;

class GroupError extends Error {
  constructor(
    readonly code: string,
    readonly status = 400,
  ) {
    super(code);
  }
}

interface MemberRow {
  member_id: string;
  name: string;
  owner: number;
  visible: number;
  stats: string | null;
  updated_at: number;
  me: number;
}
interface GroupRow {
  id: string;
  code: string;
  name: string;
  created_at: number;
}

export function isGroupPath(path: string) {
  return path === "/groups" || path.startsWith("/groups/") || path === "/me";
}

function randomHex(bytes: number) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
}
export function newCode() {
  let code = "";
  // Rejection sampling keeps every character equally likely.
  const limit = 256 - (256 % CODE_ALPHABET.length);
  while (code.length < CODE_LENGTH) {
    for (const b of crypto.getRandomValues(new Uint8Array(16))) {
      if (b < limit && code.length < CODE_LENGTH)
        code += CODE_ALPHABET[b % CODE_ALPHABET.length];
    }
  }
  return code;
}
export function formatCode(code: string) {
  return code.slice(0, 4) + "-" + code.slice(4);
}
/** Accepts "abcd-efgh", "ABCD EFGH", ".../g/ABCDEFGH" and "...?code=ABCD-EFGH". */
export function normalizeCode(value: unknown) {
  if (typeof value !== "string" || value.length > 512) return null;
  let raw = value.trim();
  const query = /(?:^|[?&#])code=([^&#]*)/i.exec(raw);
  const path = /\/g\/([A-Za-z0-9 %-]+)/i.exec(raw);
  const part = query?.[1] ?? path?.[1];
  if (part !== undefined) {
    try {
      raw = decodeURIComponent(part.replace(/\+/g, " "));
    } catch {
      return null;
    }
  }
  const code = raw.toUpperCase().replace(/[\s-]/g, "");
  return codePattern.test(code) ? code : null;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function cleanText(value: unknown, min: number, max: number) {
  if (typeof value !== "string" || value.length > max * 4) return null;
  const text = value.trim();
  const length = [...text].length;
  if (length < min || length > max || controlPattern.test(text)) return null;
  return text;
}
function parseName(value: unknown, max: number, error: string) {
  const name = cleanText(value, 1, max);
  if (name === null) throw new GroupError(error);
  return name;
}
const int = (value: unknown, min: number, max: number) =>
  Number.isInteger(value) &&
  (value as number) >= min &&
  (value as number) <= max;
function validDate(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value))
    return false;
  const date = new Date(value + "T00:00:00Z");
  return (
    !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value
  );
}
/** Returns the canonical JSON to store, or null for "no statistics". */
export function parseStats(value: unknown): string | null {
  if (value === null) return null;
  if (!isObject(value)) throw new GroupError("invalid_stats");
  const keys = Object.keys(value);
  if (
    STAT_KEYS.some((k) => !keys.includes(k)) ||
    keys.some(
      (k) =>
        !(STAT_KEYS as readonly string[]).includes(k) &&
        !(OPTIONAL_STAT_KEYS as readonly string[]).includes(k),
    )
  )
    throw new GroupError("invalid_stats");
  const s = value;
  const plan = cleanText(s.plan, 0, 60);
  if (
    !int(s.chapters, 0, 2000) ||
    !int(s.total, 1, 2000) ||
    (s.chapters as number) > (s.total as number) ||
    !int(s.weekChapters, 0, 2000) ||
    !int(s.streak, 0, 10000) ||
    !int(s.minutes, 0, 1000000) ||
    !(s.wpm === null || int(s.wpm, 0, 2000)) ||
    !(s.lastRead === null || validDate(s.lastRead)) ||
    !(s.progress === undefined || int(s.progress, 0, 10000)) ||
    plan === null
  )
    throw new GroupError("invalid_stats");
  return JSON.stringify({
    chapters: s.chapters,
    total: s.total,
    weekChapters: s.weekChapters,
    streak: s.streak,
    minutes: s.minutes,
    wpm: s.wpm,
    lastRead: s.lastRead,
    plan,
    ...(s.progress === undefined ? {} : { progress: s.progress }),
  });
}
function parseVisible(value: unknown, fallback?: boolean) {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== "boolean") throw new GroupError("invalid_request");
  return value;
}

async function readJson(request: Request, allowed: string[]) {
  if (!request.headers.get("Content-Type")?.startsWith("application/json"))
    throw new GroupError("unsupported_media_type", 415);
  const text = await readLimitedText(request);
  if (text === null) throw new GroupError("too_large", 413);
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new GroupError("invalid_request");
  }
  if (!isObject(body) || Object.keys(body).some((k) => !allowed.includes(k)))
    throw new GroupError("invalid_request");
  return body;
}

async function count(db: D1Database, sql: string, ...values: unknown[]) {
  const row = await db
    .prepare(sql)
    .bind(...values)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function groupView(db: D1Database, groupId: string, tokenHash: string) {
  const group = await db
    .prepare("SELECT id, code, name, created_at FROM groups WHERE id = ?")
    .bind(groupId)
    .first<GroupRow>();
  const rows = (
    await db
      .prepare(
        `SELECT member_id, name, owner, visible, stats, updated_at, token_hash = ? AS me
        FROM members WHERE group_id = ?`,
      )
      .bind(tokenHash, groupId)
      .all<MemberRow>()
  ).results;
  const self = rows.find((row) => row.me);
  if (!group || !self) throw new GroupError("group_not_found", 404);
  // Hidden members are only counted; their names and statistics never leave the server.
  const members = rows
    .filter((row) => row.me || row.visible)
    .map((row) => ({
      memberId: row.member_id,
      name: row.name,
      owner: !!row.owner,
      me: !!row.me,
      stats: row.stats ? JSON.parse(row.stats) : null,
      updatedAt: row.updated_at,
    }))
    .sort(
      (a, b) =>
        a.name.localeCompare(b.name) || a.memberId.localeCompare(b.memberId),
    );
  return {
    id: group.id,
    name: group.name,
    code: formatCode(group.code),
    createdAt: group.created_at,
    owner: !!self.owner,
    me: { memberId: self.member_id, name: self.name, visible: !!self.visible },
    hiddenCount: rows.filter((row) => !row.me && !row.visible).length,
    members,
  };
}

async function membership(db: D1Database, groupId: string, tokenHash: string) {
  if (!groupIdPattern.test(groupId))
    throw new GroupError("group_not_found", 404);
  const row = await db
    .prepare(
      "SELECT member_id, owner FROM members WHERE group_id = ? AND token_hash = ?",
    )
    .bind(groupId, tokenHash)
    .first<{ member_id: string; owner: number }>();
  if (!row) throw new GroupError("group_not_found", 404);
  return row;
}
async function requireOwner(db: D1Database, groupId: string, tokenHash: string) {
  const row = await membership(db, groupId, tokenHash);
  if (!row.owner) throw new GroupError("forbidden", 403);
  return row;
}

/** After members left: hand ownership to the oldest member, drop empty groups. */
function cleanup(db: D1Database, groupId: string): D1PreparedStatement[] {
  return [
    db
      .prepare(
        `UPDATE members SET owner = 1 WHERE group_id = ? AND member_id = (
          SELECT member_id FROM members WHERE group_id = ? ORDER BY joined_at, member_id LIMIT 1)
        AND NOT EXISTS (SELECT 1 FROM members WHERE group_id = ? AND owner = 1)`,
      )
      .bind(groupId, groupId, groupId),
    db
      .prepare(
        "DELETE FROM groups WHERE id = ? AND NOT EXISTS (SELECT 1 FROM members WHERE group_id = ?)",
      )
      .bind(groupId, groupId),
  ];
}

async function createGroup(
  request: Request,
  db: D1Database,
  tokenHash: string,
  now: number,
) {
  const body = await readJson(request, [
    "groupName",
    "name",
    "stats",
    "visible",
  ]);
  const groupName = parseName(body.groupName, 60, "invalid_group_name");
  const name = parseName(body.name, 40, "invalid_name");
  const stats = body.stats === undefined ? null : parseStats(body.stats);
  const visible = parseVisible(body.visible, true);
  if ((await count(db, "SELECT COUNT(*) AS count FROM groups")) >= MAX_GROUPS)
    throw new GroupError("capacity_reached", 503);
  if (
    (await count(
      db,
      "SELECT COUNT(*) AS count FROM members WHERE token_hash = ?",
      tokenHash,
    )) >= MAX_GROUPS_PER_TOKEN
  )
    throw new GroupError("too_many_groups", 409);
  for (let attempt = 0; attempt < 8; attempt++) {
    const id = randomHex(16),
      code = newCode();
    // A colliding code is ignored and the member insert then finds no group.
    const [inserted] = await db.batch([
      db
        .prepare(
          "INSERT OR IGNORE INTO groups (id, code, name, created_at) VALUES (?, ?, ?, ?)",
        )
        .bind(id, code, groupName, now),
      db
        .prepare(
          `INSERT INTO members (group_id, member_id, token_hash, name, owner, visible, stats, joined_at, updated_at)
          SELECT ?, ?, ?, ?, 1, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM groups WHERE id = ? AND code = ?)`,
        )
        .bind(
          id,
          randomHex(12),
          tokenHash,
          name,
          visible ? 1 : 0,
          stats,
          now,
          now,
          id,
          code,
        ),
    ]);
    if (inserted.meta.changes) return groupView(db, id, tokenHash);
  }
  throw new GroupError("unavailable", 503);
}

async function joinGroup(
  request: Request,
  db: D1Database,
  tokenHash: string,
  now: number,
) {
  const body = await readJson(request, ["code", "name", "stats", "visible"]);
  const code = normalizeCode(body.code);
  if (!code) throw new GroupError("invalid_code");
  const name = parseName(body.name, 40, "invalid_name");
  const stats = body.stats === undefined ? undefined : parseStats(body.stats);
  const visible =
    body.visible === undefined ? undefined : parseVisible(body.visible);
  const group = await db
    .prepare("SELECT id FROM groups WHERE code = ?")
    .bind(code)
    .first<{ id: string }>();
  if (!group) throw new GroupError("group_not_found", 404);
  const existing = await db
    .prepare("SELECT 1 FROM members WHERE group_id = ? AND token_hash = ?")
    .bind(group.id, tokenHash)
    .first();
  if (existing) {
    // Rejoining only refreshes the provided fields.
    await db
      .prepare(
        `UPDATE members SET name = ?, stats = CASE WHEN ? THEN ? ELSE stats END,
        visible = COALESCE(?, visible), updated_at = ? WHERE group_id = ? AND token_hash = ?`,
      )
      .bind(
        name,
        stats === undefined ? 0 : 1,
        stats ?? null,
        visible === undefined ? null : visible ? 1 : 0,
        now,
        group.id,
        tokenHash,
      )
      .run();
    return groupView(db, group.id, tokenHash);
  }
  if (
    (await count(
      db,
      "SELECT COUNT(*) AS count FROM members WHERE token_hash = ?",
      tokenHash,
    )) >= MAX_GROUPS_PER_TOKEN
  )
    throw new GroupError("too_many_groups", 409);
  const result = await db
    .prepare(
      `INSERT OR IGNORE INTO members (group_id, member_id, token_hash, name, owner, visible, stats, joined_at, updated_at)
      SELECT ?, ?, ?, ?, 0, ?, ?, ?, ?
      WHERE EXISTS (SELECT 1 FROM groups WHERE id = ?)
      AND (SELECT COUNT(*) FROM members WHERE group_id = ?) < ?`,
    )
    .bind(
      group.id,
      randomHex(12),
      tokenHash,
      name,
      visible === false ? 0 : 1,
      stats ?? null,
      now,
      now,
      group.id,
      group.id,
      MAX_MEMBERS,
    )
    .run();
  if (!result.meta.changes) {
    const joined = await db
      .prepare("SELECT 1 FROM members WHERE group_id = ? AND token_hash = ?")
      .bind(group.id, tokenHash)
      .first();
    if (!joined) {
      const members = await count(
        db,
        "SELECT COUNT(*) AS count FROM members WHERE group_id = ?",
        group.id,
      );
      if (members >= MAX_MEMBERS) throw new GroupError("group_full", 409);
      throw new GroupError("group_not_found", 404);
    }
  }
  return groupView(db, group.id, tokenHash);
}

async function leave(db: D1Database, groupId: string, tokenHash: string) {
  if (!groupIdPattern.test(groupId))
    throw new GroupError("group_not_found", 404);
  const [removed] = await db.batch([
    db
      .prepare("DELETE FROM members WHERE group_id = ? AND token_hash = ?")
      .bind(groupId, tokenHash),
    ...cleanup(db, groupId),
  ]);
  if (!removed.meta.changes) throw new GroupError("group_not_found", 404);
  return { left: true };
}

async function deleteMe(db: D1Database, tokenHash: string) {
  const groups = (
    await db
      .prepare("SELECT group_id FROM members WHERE token_hash = ?")
      .bind(tokenHash)
      .all<{ group_id: string }>()
  ).results;
  if (!groups.length) return { deleted: 0 };
  const [removed] = await db.batch([
    db.prepare("DELETE FROM members WHERE token_hash = ?").bind(tokenHash),
    ...groups.flatMap((row) => cleanup(db, row.group_id)),
  ]);
  return { deleted: removed.meta.changes };
}

async function route(
  request: Request,
  db: D1Database,
  tokenHash: string,
  now: number,
): Promise<[unknown, number?]> {
  const method = request.method;
  const parts = new URL(request.url).pathname.split("/").filter(Boolean);
  const [root, groupId, sub, memberId] = parts;
  const notAllowed = new GroupError("method_not_allowed", 405);
  if (root === "me" && parts.length === 1) {
    if (method === "PUT") {
      const body = await readJson(request, ["name", "stats"]);
      const name = parseName(body.name, 40, "invalid_name");
      if (!("stats" in body)) throw new GroupError("invalid_stats");
      const stats = parseStats(body.stats);
      const result = await db
        .prepare(
          "UPDATE members SET name = ?, stats = ?, updated_at = ? WHERE token_hash = ?",
        )
        .bind(name, stats, now, tokenHash)
        .run();
      return [{ updated: result.meta.changes }];
    }
    if (method === "DELETE") return [await deleteMe(db, tokenHash)];
    throw notAllowed;
  }
  if (root !== "groups" || parts.length > 4)
    throw new GroupError("not_found", 404);
  if (parts.length === 1) {
    if (method === "POST")
      return [{ group: await createGroup(request, db, tokenHash, now) }, 201];
    if (method === "GET") {
      const rows = (
        await db
          .prepare(
            `SELECT g.id, g.name, g.code, m.owner,
            (SELECT COUNT(*) FROM members x WHERE x.group_id = g.id) AS member_count
            FROM members m JOIN groups g ON g.id = m.group_id
            WHERE m.token_hash = ? ORDER BY m.joined_at, g.id`,
          )
          .bind(tokenHash)
          .all<{
            id: string;
            name: string;
            code: string;
            owner: number;
            member_count: number;
          }>()
      ).results;
      return [
        {
          groups: rows.map((row) => ({
            id: row.id,
            name: row.name,
            code: formatCode(row.code),
            memberCount: row.member_count,
            owner: !!row.owner,
          })),
        },
      ];
    }
    throw notAllowed;
  }
  if (parts.length === 2 && groupId === "join") {
    if (method !== "POST") throw notAllowed;
    return [{ group: await joinGroup(request, db, tokenHash, now) }];
  }
  if (parts.length === 2) {
    if (method !== "GET") throw notAllowed;
    await membership(db, groupId, tokenHash);
    return [{ group: await groupView(db, groupId, tokenHash) }];
  }
  if (parts.length === 3 && sub === "me") {
    if (method === "PUT") {
      const body = await readJson(request, ["visible"]);
      const visible = parseVisible(body.visible);
      await membership(db, groupId, tokenHash);
      await db
        .prepare(
          "UPDATE members SET visible = ?, updated_at = ? WHERE group_id = ? AND token_hash = ?",
        )
        .bind(visible ? 1 : 0, now, groupId, tokenHash)
        .run();
      return [{ group: await groupView(db, groupId, tokenHash) }];
    }
    if (method === "DELETE") return [await leave(db, groupId, tokenHash)];
    throw notAllowed;
  }
  if (parts.length === 3 && sub === "code") {
    if (method !== "POST") throw notAllowed;
    await requireOwner(db, groupId, tokenHash);
    for (let attempt = 0; attempt < 8; attempt++) {
      const result = await db
        .prepare("UPDATE OR IGNORE groups SET code = ? WHERE id = ?")
        .bind(newCode(), groupId)
        .run();
      if (result.meta.changes)
        return [{ group: await groupView(db, groupId, tokenHash) }];
    }
    throw new GroupError("unavailable", 503);
  }
  if (parts.length === 4 && sub === "members") {
    if (method !== "DELETE") throw notAllowed;
    const self = await requireOwner(db, groupId, tokenHash);
    if (!memberIdPattern.test(memberId))
      throw new GroupError("member_not_found", 404);
    if (memberId === self.member_id)
      throw new GroupError("cannot_remove_self");
    const result = await db
      .prepare(
        "DELETE FROM members WHERE group_id = ? AND member_id = ? AND token_hash != ?",
      )
      .bind(groupId, memberId, tokenHash)
      .run();
    if (!result.meta.changes) throw new GroupError("member_not_found", 404);
    return [{ group: await groupView(db, groupId, tokenHash) }];
  }
  throw new GroupError("not_found", 404);
}

export async function handleGroups(
  request: Request,
  env: Env,
  headers: Headers,
  now = Date.now(),
) {
  const reply = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers });
  const origin = request.headers.get("Origin");
  if (origin !== null && origin !== env.APP_ORIGIN)
    return reply({ error: "origin_not_allowed" }, 403);
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  const token =
    request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (!tokenPattern.test(token)) return reply({ error: "unauthorized" }, 401);
  const tokenHash = await digest(token);
  // A whole class may share one school IP, so the limit follows the installation.
  if (
    !env.GROUP_LIMIT ||
    !(await env.GROUP_LIMIT.limit({ key: tokenHash })).success
  )
    return reply({ error: "rate_limited" }, 429);
  try {
    const [data, status] = await route(request, env.DB, tokenHash, now);
    return reply(data, status);
  } catch (error) {
    if (error instanceof GroupError)
      return reply({ error: error.code }, error.status);
    return reply({ error: "unavailable" }, 503);
  }
}
