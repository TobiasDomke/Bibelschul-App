import {
  buildPushPayload,
  type PushSubscription as Subscription,
} from "@block65/webcrypto-web-push";
import type {
  D1Database,
  RateLimit,
  ExportedHandler,
} from "@cloudflare/workers-types";
import { localDate, nextReminder } from "./schedule";
import { handleGroups, isGroupPath } from "./groups";
import { languageCodes, type Lang } from "../lib/languages";

export interface Env {
  DB: D1Database;
  API_LIMIT: RateLimit;
  GROUP_LIMIT: RateLimit;
  APP_ORIGIN: string;
  VAPID_PUBLIC_KEY: string;
  VAPID_PRIVATE_KEY: string;
}
export interface Reminder {
  id: string;
  token_hash: string;
  subscription: string;
  time: string;
  timezone: string;
  language: Lang;
  next_run: number;
  last_sent_date: string | null;
  lease_until: number;
  failures: number;
  last_test: number;
  revision: number;
  updated_at: number;
}
type Sender = (row: Reminder, env: Env, test?: boolean) => Promise<number>;
const languages = languageCodes;
export const MAX_BODY = 4096;
const MAX_SUBSCRIPTIONS = 1000;
export const tokenPattern = /^[A-Za-z0-9_-]{43}$/;

export async function digest(value: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
/** Reads at most `max` bytes of the body; returns null when it is larger. */
export async function readLimitedText(request: Request, max = MAX_BODY) {
  if (Number(request.headers.get("Content-Length") ?? 0) > max) return null;
  const reader = request.body?.getReader();
  if (!reader) return "";
  let bytes = 0,
    text = "";
  const decoder = new TextDecoder();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > max) {
      await reader.cancel();
      return null;
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}
function base64Length(value: unknown, size: number) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value))
    return false;
  try {
    return atob(value.replace(/-/g, "+").replace(/_/g, "/")).length === size;
  } catch {
    return false;
  }
}
export function validEndpoint(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      url.port ||
      url.username ||
      url.password ||
      url.hash
    )
      return false;
    return (
      (url.hostname === "fcm.googleapis.com" &&
        url.pathname.startsWith("/fcm/send/")) ||
      (url.hostname.endsWith(".push.apple.com") && url.pathname.length > 1) ||
      (url.hostname.endsWith(".push.services.mozilla.com") &&
        url.pathname.startsWith("/wpush/")) ||
      (url.hostname.endsWith(".notify.windows.com") &&
        url.pathname.startsWith("/"))
    );
  } catch {
    return false;
  }
}
function parseSettings(body: unknown) {
  if (!body || typeof body !== "object") throw new Error("invalid_settings");
  const data = body as Record<string, any>;
  if (
    Object.keys(data).some(
      (k) => !["subscription", "time", "timezone", "language"].includes(k),
    )
  )
    throw new Error("invalid_settings");
  if (
    typeof data.time !== "string" ||
    !/^([01]\d|2[0-3]):[0-5]\d$/.test(data.time) ||
    typeof data.timezone !== "string" ||
    data.timezone.length > 80 ||
    !languages.includes(data.language)
  )
    throw new Error("invalid_settings");
  try {
    localDate(Date.now(), data.timezone);
  } catch {
    throw new Error("invalid_settings");
  }
  const sub = data.subscription;
  if (
    !sub ||
    !validEndpoint(sub.endpoint) ||
    !base64Length(sub.keys?.p256dh, 65) ||
    !base64Length(sub.keys?.auth, 16)
  )
    throw new Error("invalid_subscription");
  if (
    atob(sub.keys.p256dh.replace(/-/g, "+").replace(/_/g, "/")).charCodeAt(
      0,
    ) !== 4
  )
    throw new Error("invalid_subscription");
  return {
    time: data.time as string,
    timezone: data.timezone as string,
    language: data.language as Reminder["language"],
    subscription: {
      endpoint: sub.endpoint,
      expirationTime: null,
      keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth },
    } as Subscription,
  };
}
function notification(row: Reminder, env: Env, test: boolean) {
  const messages = {
    de: test
      ? "Deine Testnachricht ist angekommen. Die tägliche Erinnerung ist bereit."
      : "Zeit zum Bibellesen. Öffne Leseweg für deine heutigen Kapitel.",
    ru: test
      ? "Проверочное уведомление доставлено. Ежедневные напоминания готовы."
      : "Время читать Библию. Открой Leseweg, чтобы увидеть главы на сегодня.",
    en: test
      ? "Your test notification has arrived. Daily reminders are ready."
      : "Time to read your Bible. Open Leseweg for today's chapters.",
    uk: test
      ? "Тестове сповіщення надійшло. Щоденні нагадування готові."
      : "Час читати Біблію. Відкрий Leseweg, щоб побачити розділи на сьогодні.",
  };
  return {
    web_push: 8030,
    notification: {
      title: "Leseweg",
      body: messages[row.language],
      lang: row.language,
      navigate: env.APP_ORIGIN + "/",
      icon: env.APP_ORIGIN + "/icon-192.png",
      tag: test ? "leseweg-test" : "leseweg-daily",
      silent: false,
    },
  };
}
export async function sendPush(row: Reminder, env: Env, test = false) {
  const subscription = JSON.parse(row.subscription) as Subscription;
  if (!validEndpoint(subscription.endpoint)) return 410;
  let stage = "encryption";
  try {
    const payload = await buildPushPayload(
      {
        data: notification(row, env, test),
        options: {
          ttl: test ? 300 : 3600,
          urgency: test ? "high" : "normal",
          // Apple validates base64url decoding as well as the character set.
          topic: btoa(test ? "leseweg-test" : "leseweg-daily")
            .replace(/\+/g, "-")
            .replace(/\//g, "_")
            .replace(/=/g, ""),
        },
      },
      subscription,
      {
        subject: env.APP_ORIGIN,
        publicKey: env.VAPID_PUBLIC_KEY,
        privateKey: env.VAPID_PRIVATE_KEY,
      },
    );
    stage = "request";
    const response = await fetch(subscription.endpoint, {
      ...payload,
      // Workers supports manual/follow only. Never forward VAPID credentials
      // to a redirect target: a 3xx response is handled as a failed delivery.
      redirect: "manual",
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      let reason = "";
      try {
        const body = (await response.json()) as { reason?: unknown };
        if (
          typeof body.reason === "string" &&
          /^[A-Za-z0-9_]{1,80}$/.test(body.reason)
        )
          reason = body.reason;
      } catch {
        /* Providers do not always return a JSON error. */
      }
      console.warn("push_delivery_failed", {
        stage,
        status: response.status,
        reason,
      });
    } else await response.body?.cancel();
    return response.status;
  } catch (error) {
    let message = error instanceof Error ? error.message : "Unknown error";
    for (const value of [
      subscription.endpoint,
      subscription.keys.auth,
      subscription.keys.p256dh,
      env.VAPID_PRIVATE_KEY,
      env.VAPID_PUBLIC_KEY,
    ]) {
      if (value) message = message.split(value).join("[redacted]");
    }
    message = message.replace(/https?:\/\/\S+/g, "[redacted]").slice(0, 200);
    console.warn("push_delivery_failed", {
      stage,
      name: error instanceof Error ? error.name : "Error",
      message,
    });
    throw error;
  }
}

export async function handleRequest(
  request: Request,
  env: Env,
  sender: Sender = sendPush,
  now = Date.now(),
) {
  const headers = new Headers({
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    Vary: "Origin",
  });
  const origin = request.headers.get("Origin");
  if (origin === env.APP_ORIGIN) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set(
      "Access-Control-Allow-Methods",
      "GET, PUT, DELETE, POST, OPTIONS",
    );
    headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  }
  const reply = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers });
  const path = new URL(request.url).pathname;
  if (request.method === "GET" && path === "/config")
    return reply({
      publicKey: env.VAPID_PUBLIC_KEY,
      available: !!env.VAPID_PUBLIC_KEY && !!env.VAPID_PRIVATE_KEY,
    });
  // Reading groups are also used by the native app, which sends no Origin.
  if (isGroupPath(path)) return handleGroups(request, env, headers, now);
  if (origin !== env.APP_ORIGIN)
    return reply({ error: "origin_not_allowed" }, 403);
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  const token =
    request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (!tokenPattern.test(token)) return reply({ error: "unauthorized" }, 401);
  if (
    !env.API_LIMIT ||
    !(
      await env.API_LIMIT.limit({
        key: await digest(request.headers.get("CF-Connecting-IP") ?? "unknown"),
      })
    ).success
  )
    return reply({ error: "rate_limited" }, 429);
  const tokenHash = await digest(token);
  try {
    if (request.method === "PUT" && path === "/subscription") {
      if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY)
        return reply({ error: "unavailable" }, 503);
      if (!request.headers.get("Content-Type")?.startsWith("application/json"))
        return reply({ error: "invalid_settings" }, 415);
      const text = await readLimitedText(request);
      if (text === null) return reply({ error: "too_large" }, 413);
      let data: ReturnType<typeof parseSettings>;
      try {
        data = parseSettings(JSON.parse(text));
      } catch {
        return reply({ error: "invalid_settings" }, 400);
      }
      const id = await digest(data.subscription.endpoint);
      const existing = await env.DB.prepare(
        "SELECT * FROM reminders WHERE id = ? OR token_hash = ?",
      )
        .bind(id, tokenHash)
        .all<Reminder>();
      if (
        existing.results.some(
          (row) => row.id === id && row.token_hash !== tokenHash,
        )
      )
        return reply({ error: "subscription_conflict" }, 409);
      const previous = existing.results.find(
        (row) => row.token_hash === tokenHash,
      );
      const count = await env.DB.prepare(
        "SELECT COUNT(*) AS count FROM reminders",
      ).first<{ count: number }>();
      if (!previous && (count?.count ?? 0) >= MAX_SUBSCRIPTIONS)
        return reply({ error: "capacity_reached" }, 503);
      const next = nextReminder(
        now,
        data.time,
        data.timezone,
        previous?.last_sent_date ?? null,
      );
      // Token identifies this installation even if its browser rotates the push endpoint.
      await env.DB.prepare(
        `INSERT INTO reminders (id, token_hash, subscription, time, timezone, language, next_run, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(token_hash) DO UPDATE SET id=excluded.id, subscription=excluded.subscription, time=excluded.time,
        timezone=excluded.timezone, language=excluded.language, next_run=excluded.next_run, updated_at=excluded.updated_at,
        lease_until=0, failures=0, revision=reminders.revision+1`,
      )
        .bind(
          id,
          tokenHash,
          JSON.stringify(data.subscription),
          data.time,
          data.timezone,
          data.language,
          next,
          now,
        )
        .run();
      return reply({
        enabled: true,
        nextRun: next,
        time: data.time,
        timezone: data.timezone,
        language: data.language,
      });
    }
    if (request.method === "DELETE" && path === "/subscription") {
      await env.DB.prepare("DELETE FROM reminders WHERE token_hash = ?")
        .bind(tokenHash)
        .run();
      return reply({ enabled: false });
    }
    if (path !== "/subscription" && path !== "/test")
      return reply({ error: "not_found" }, 404);
    const row = await env.DB.prepare(
      "SELECT * FROM reminders WHERE token_hash = ?",
    )
      .bind(tokenHash)
      .first<Reminder>();
    if (!row) return reply({ enabled: false }, 404);
    if (request.method === "GET" && path === "/subscription")
      return reply({
        enabled: true,
        time: row.time,
        timezone: row.timezone,
        language: row.language,
        nextRun: row.next_run,
      });
    if (request.method === "POST" && path === "/test") {
      const claim = await env.DB.prepare(
        "UPDATE reminders SET last_test = ? WHERE token_hash = ? AND last_test <= ? RETURNING id",
      )
        .bind(now, tokenHash, now - 60000)
        .first();
      if (!claim) return reply({ error: "rate_limited" }, 429);
      const status = await sender(row, env, true);
      if (status === 404 || status === 410) {
        await env.DB.prepare(
          "DELETE FROM reminders WHERE id = ? AND revision = ?",
        )
          .bind(row.id, row.revision)
          .run();
        return reply({ error: "subscription_expired" }, 410);
      }
      return status >= 200 && status < 300
        ? reply({ sent: true })
        : reply({ error: "push_failed" }, 502);
    }
    return reply({ error: "method_not_allowed" }, 405);
  } catch {
    return reply({ error: "unavailable" }, 503);
  }
}

export async function runScheduled(
  env: Env,
  now = Date.now(),
  sender: Sender = sendPush,
) {
  // Bound work to the free plan's CPU/subrequest budget. Larger bursts queue for the next minute.
  const due = await env.DB.prepare(
    "SELECT id FROM reminders WHERE next_run <= ? AND lease_until <= ? ORDER BY next_run LIMIT 5",
  )
    .bind(now, now)
    .all<{ id: string }>();
  for (const { id } of due.results) {
    const row = await env.DB.prepare(
      "UPDATE reminders SET lease_until = ? WHERE id = ? AND next_run <= ? AND lease_until <= ? RETURNING *",
    )
      .bind(now + 120000, id, now, now)
      .first<Reminder>();
    if (!row) continue;
    let status = 503;
    const missed = now - row.next_run > 6 * 3600000;
    const sentDate = localDate(now, row.timezone);
    if (missed || row.last_sent_date === sentDate) status = 204;
    else {
      try {
        status = await sender(row, env);
      } catch {
        /* retry transient delivery errors */
      }
    }
    if (status === 404 || status === 410) {
      await env.DB.prepare(
        "DELETE FROM reminders WHERE id = ? AND revision = ?",
      )
        .bind(id, row.revision)
        .run();
    } else if (status >= 200 && status < 300) {
      const next = nextReminder(now, row.time, row.timezone, sentDate);
      await env.DB.prepare(
        "UPDATE reminders SET next_run=?, last_sent_date=?, lease_until=0, failures=0 WHERE id=? AND revision=?",
      )
        .bind(next, sentDate, id, row.revision)
        .run();
    } else {
      const failures = row.failures + 1;
      // Never retry a failed endpoint indefinitely or deliver stale reminders days later.
      const next =
        failures >= 4
          ? nextReminder(now, row.time, row.timezone)
          : now + Math.min(3600000, 60000 * 2 ** failures);
      await env.DB.prepare(
        "UPDATE reminders SET next_run=?, lease_until=0, failures=? WHERE id=? AND revision=?",
      )
        .bind(next, failures >= 4 ? 0 : failures, id, row.revision)
        .run();
    }
  }
}
export default {
  fetch: (request: Request, env: Env) => handleRequest(request, env),
  scheduled: (_controller, env, ctx) => {
    ctx.waitUntil(runScheduled(env));
  },
} satisfies ExportedHandler<Env>;
