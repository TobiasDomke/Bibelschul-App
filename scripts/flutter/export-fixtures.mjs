// Records reference results of the TypeScript web app so the Flutter port can be
// checked for identical behaviour (bibelschul_app/test/parity_test.dart).
// Run from the repository root: node scripts/flutter/export-fixtures.mjs
import { build } from "esbuild";
import { writeFile, mkdir } from "node:fs/promises";

await build({
  stdin: {
    contents: `
      export * from "./lib/planner.ts";
      export { applyAction } from "./lib/actions.ts";
      export { readingPlan, sessionChapters, nextExtraChapter, prepareState } from "./lib/adaptive.ts";
      export { readingPace, estimatedMinutes } from "./lib/pace.ts";
      export { readingTimeSummary, readingTime, readingTimeClock } from "./lib/reading-time.ts";
      export { calendarFile, csvFile, zonedUTC } from "./lib/exports.ts";
      export { makeBackup, parseBackup } from "./lib/backup.ts";
      export { deadlineBounds } from "./lib/deadline.ts";
      export { dailySeconds, sessionsFor } from "./lib/session-stats.ts";
      export { legacyReferences } from "./lib/chapter-migration.ts";`,
    resolveDir: ".",
    loader: "ts",
  },
  outfile: ".test-runtime/fixture-export.js",
  bundle: true,
  platform: "node",
  format: "esm",
});
const L = await import("../../.test-runtime/fixture-export.js");

// Deterministic pseudo-random numbers (mulberry32).
function rng(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
let opCounter = 0;
const opId = () => {
  const n = (++opCounter).toString(16).padStart(12, "0");
  return `00000000-0000-4000-8000-${n}`;
};

// 1. Chapter orders and day partitions.
const editions = ["schlachter2000", "kjv", "synodal", "ohienko"];
const orders = {};
const plans = [];
for (const edition of editions)
  for (const scope of ["bible", "ot", "nt"])
    for (const order of ["canonical", "chronological", "mixed"])
      for (const bookOrder of ["western", "eastern"]) {
        const base = { edition, scope, order, bookOrder, start: "2026-03-20", time: "07:30", timezone: "Europe/Berlin" };
        orders[`${edition}:${scope}:${order}:${bookOrder}`] = L.orderedChapters(base).map((c) => c.id);
        for (const keepTogether of [false, true])
          for (const [amount, unit] of [[1, "days"], [10, "days"], [100, "days"], [365, "days"], [2000, "days"], [7, "weeks"], [12, "months"], [5, "months"]]) {
            const config = { ...base, keepTogether, amount, unit };
            const scoped = L.scopeChapters(config);
            const previouslyRead = scoped.filter((_, i) => i % 7 === 3 || i < 15).map((c) => c.id);
            for (const prior of [[], previouslyRead]) {
              const plan = L.createPlan(config, prior);
              plans.push({ config, prior: prior.length ? "sample" : "none", lengths: plan.map((d) => d.chapters.length), first: plan[0].date, last: plan.at(-1).date });
            }
          }
      }
const bible52 = L.createPlan(L.bible52Config({ amount: 1, unit: "days", start: "2026-01-05", time: "07:30", timezone: "UTC" })).map((d) => d.chapters.map((c) => c.id));
const durations = [];
for (const start of ["2026-01-31", "2028-02-29", "2026-08-31", "2027-10-31"])
  for (const amount of [1, 2, 11, 12, 13, 119]) durations.push({ start, amount, days: L.duration({ amount, unit: "months", start, time: "07:30", timezone: "UTC" }) });
const zoned = [];
for (const [date, time, zone] of [["2026-03-29", "02:30", "Europe/Berlin"], ["2026-10-25", "02:30", "Europe/Berlin"], ["2026-03-08", "02:15", "America/New_York"], ["2026-11-01", "01:30", "America/New_York"], ["2026-06-01", "07:30", "Asia/Almaty"], ["2026-12-31", "23:59", "Pacific/Auckland"]])
  zoned.push({ date, time, zone, ms: L.zonedUTC(date, time, zone).getTime() });
const times = [0, 1, 59, 60, 89, 90, 3599, 3600, 16860, 86400, 123456.7].map((s) => ({ s, de: L.readingTime(s, "de"), en: L.readingTime(s, "en"), ru: L.readingTime(s, "ru"), uk: L.readingTime(s, "uk"), clock: L.readingTimeClock(s) }));

// 2. Simulated reading histories through applyAction.
const day = 86400000;
const scenarios = [];
const strip = (s) => (s ? { ...s, id: "PLAN" } : s);
function snapshot(state, now, lang) {
  const realNow = Date.now;
  Date.now = () => now;
  try {
  const date = L.today(state.config.timezone, now);
  const prepared = L.prepareState(state, date);
  const pace = L.readingPace(state);
  const summary = L.readingTimeSummary(state, now, pace);
  const plan = L.readingPlan(state, date);
    return {
    state: strip(JSON.parse(JSON.stringify(state))),
    planLengths: plan.map((d) => d.chapters.length),
    pace: { ...pace },
    summary: { ...summary },
    csv: L.csvFile(state, lang),
    ics: L.calendarFile(state, lang, "https://leseweg.pages.dev").replace(/DTSTAMP:\d+T\d+Z/g, "DTSTAMP:X").replaceAll(state.id, "PLAN"),
    backup: strip(JSON.parse(L.makeBackup(state, lang, "dark", now)).state),
    bounds: L.isBible52(state.config) ? null : L.deadlineBounds(state, date),
    daily: L.dailySeconds(state, now),
    session: L.sessionChapters(prepared, prepared.timer?.day ?? Math.min(plan.length - 1, Math.max(0, Math.round((Date.parse(date) - Date.parse(state.config.start)) / day)))).map((c) => c.id),
  };
  } finally {
    Date.now = realNow;
  }
}
const configs = [];
for (const edition of editions) {
  configs.push({ edition, scope: "bible", order: "canonical", keepTogether: true, bookOrderMode: "auto", amount: 3, unit: "months", timezone: "Europe/Berlin" });
  configs.push({ edition, scope: "nt", order: "chronological", keepTogether: true, bookOrderMode: "manual", bookOrder: "eastern", amount: 30, unit: "days", timezone: "America/New_York" });
  configs.push({ edition, scope: "ot", order: "mixed", keepTogether: false, bookOrderMode: "auto", amount: 8, unit: "weeks", timezone: "Asia/Almaty" });
}
configs.push({ template: "bible52", amount: 52, unit: "weeks", timezone: "Europe/Berlin" });
configs.push({ template: "bible52", amount: 52, unit: "weeks", timezone: "America/New_York" });
const langs = ["de", "en", "ru", "uk"];
for (const [index, partial] of configs.entries()) {
  const random = rng(1000 + index);
  const lang = langs[index % 4];
  let now = Date.parse("2026-03-26T06:00:00Z") + Math.floor(random() * 3) * 3600000;
  const start = L.today(partial.timezone, now);
  const config = { start, time: "07:30", ...partial };
  const steps = [];
  let state = null;
  const scoped = () => L.scopeChapters(state.config);
  const run = (op) => {
    const full = { ...op, planId: op.action === "create" ? null : state.id, opId: opId() };
    try {
      state = L.applyAction(state, full, now);
      steps.push({ now, op: { ...full, planId: full.planId && "PLAN" }, ok: snapshot(state, now, lang) });
    } catch (e) {
      steps.push({ now, op: { ...full, planId: full.planId && "PLAN" }, error: e.message });
    }
  };
  const prior = random() < 0.5 ? [] : L.scopeChapters(L.isBible52(config) ? L.bible52Config(config) : config).slice(5, 25).map((c) => c.id);
  run({ action: "create", config, previouslyRead: prior, lang });
  for (let step = 0; step < 70; step++) {
    const r = random();
    const date = L.today(state.config.timezone, now);
    const prepared = L.prepareState(state, date);
    const fixed = L.isBible52(state.config);
    const current = fixed ? (state.timer?.day ?? state.pace?.draft?.day ?? (prepared.adaptive.finished.length ? Math.max(...prepared.adaptive.finished) + 1 : 0)) : Math.max(0, Math.min(L.duration(state.config) - 1, Math.round((Date.parse(date) - Date.parse(state.config.start)) / day)));
    const items = L.sessionChapters(prepared, Math.min(current, 363));
    if (r < 0.12) run({ action: "timer", mode: "start", day: current });
    else if (r < 0.2) { now += Math.floor(random() * 2400000); run({ action: "timer", mode: random() < 0.5 ? "pause" : "stop", day: current }); }
    else if (r < 0.45 && items.length) { const c = items[Math.floor(random() * items.length)]; run({ action: "chapter", chapter: c.id, done: random() < 0.85 }); }
    else if (r < 0.55) run({ action: "complete", day: current, ...(random() < 0.3 ? { paceChoice: random() < 0.5 ? "confirmed" : "excluded" } : {}) });
    else if (r < 0.6) run({ action: "extend", day: current });
    else if (r < 0.63) run({ action: "reopen", day: current });
    else if (r < 0.67) run({ action: "correct", day: current, minutes: Math.round(random() * 900) / 10 });
    else if (r < 0.7 && !fixed) run({ action: "deadline", end: L.addDays(date, Math.floor(random() * 60)) });
    else if (r < 0.72) run({ action: "language", lang: langs[Math.floor(random() * 4)] });
    else if (r < 0.74) run({ action: "book-order", choice: ["auto", "western", "eastern"][Math.floor(random() * 3)], lang });
    else if (r < 0.76 && !fixed) run({ action: "edition", edition: editions[Math.floor(random() * 4)] });
    else if (r < 0.77) run({ action: "review-edition" });
    else if (r < 0.79) run({ action: "previous", previouslyRead: scoped().filter((c) => !state.done[c.id]).slice(0, Math.floor(random() * 30)).map((c) => c.id) });
    else if (r < 0.81 && state.pace?.samples.length) run({ action: "review-pace", index: 0, seconds: state.pace.samples[0].seconds, review: ["auto", "confirmed", "excluded"][Math.floor(random() * 3)] });
    else if (r < 0.83) run({ action: "settings", time: "06:15", timezone: random() < 0.5 ? "Europe/Berlin" : "America/New_York", lang });
    else if (r < 0.86) run({ action: "timer", mode: "start", day: current + 1 });
    else now += Math.floor(random() * 1.6 * day);
    now += Math.floor(random() * 900000);
  }
  scenarios.push({ lang, steps });
}

// 3. Backup validation.
const backups = [];
for (const scenario of scenarios.slice(0, 6)) {
  const last = scenario.steps.filter((s) => s.ok).at(-1).ok.state;
  const raw = (state) => JSON.stringify({ app: "leseweg", version: 8, exportedAt: "2026-04-01T10:00:00.000Z", theme: "light", state: { ...state, id: "11111111-1111-4111-8111-111111111111", timer: null, ops: [] } });
  backups.push({ raw: raw(last) });
  backups.push({ raw: raw({ ...last, done: { ...last.done, 9999: "2026-01-01" } }) });
  backups.push({ raw: raw({ ...last, logs: [...last.logs, { day: 5000, seconds: 1, at: "2026-01-01T00:00:00.000Z" }] }) });
  backups.push({ raw: raw({ ...last, extraField: 1 }) });
  backups.push({ raw: raw({ ...last, adaptive: last.adaptive && { ...last.adaptive, days: last.adaptive.days.slice(1) } }) });
}
for (const b of backups) {
  try {
    b.state = strip(L.parseBackup(b.raw).state);
    b.ok = true;
  } catch {
    b.ok = false;
  }
}

// 4. Legacy installations (before chapterSchema 2) and their migration.
const oldId = (ref) => L.legacyReferences.indexOf(ref);
const legacyBase = { amount: 90, unit: "days", start: "2026-07-01", time: "07:30", timezone: "Europe/Berlin" };
const legacyAt = Date.parse("2026-07-01T10:00:00Z");
const legacyStates = [];
{
  const legacy = {
    id: "22222222-2222-4222-8222-222222222222", config: { ...legacyBase }, lang: "de", done: {}, previouslyRead: [],
    logs: [{ day: 0, seconds: 600, at: new Date(legacyAt).toISOString() }], timer: null, ops: [],
    pace: { samples: [], draft: null },
    adaptive: { date: legacyBase.start, days: Array.from({ length: 90 }, (_, i) => (i === 0 ? L.legacyReferences.map((_, id) => id) : [])), extra: {}, finished: [], unplanned: [] },
  };
  for (const ref of ["JOL 2", "JOL 3", "AMO 1", "OBA 1", "ZEC 14", "MAL 3", "MAL 4", "MAT 1"]) legacy.done[oldId(ref)] = legacyBase.start;
  legacy.previouslyRead = [oldId("JOL 1"), oldId("MAL 1")];
  legacy.adaptive.days[0] = legacy.adaptive.days[0].filter((id) => !legacy.previouslyRead.includes(id));
  legacy.pace.samples = [{ day: 0, chapters: [oldId("JOL 2"), oldId("MAL 4")], seconds: 360 }, { day: 0, chapters: [oldId("AMO 1"), oldId("MAT 1")], seconds: 240 }];
  legacyStates.push(legacy);
  // Very old: daily totals only, no pace, no adaptive, no sessions.
  const old = { id: "33333333-3333-4333-8333-333333333333", config: { ...legacyBase, amount: 3, unit: "months" }, lang: "ru", done: {}, logs: [], timer: null, ops: [] };
  for (const [i, ref] of ["GEN 1", "GEN 2", "GEN 3", "JOL 1", "MAL 4", "PSA 23"].entries()) old.done[oldId(ref)] = L.addDays(legacyBase.start, Math.floor(i / 2));
  old.logs = [0, 1, 2].map((d) => ({ day: d, seconds: 900 + d * 60, at: new Date(legacyAt + d * day).toISOString() }));
  legacyStates.push(old);
  // Open measurement on an old installation.
  const open = { ...structuredClone(old), id: "44444444-4444-4444-8444-444444444444", pace: { samples: [], draft: { day: 2, before: [oldId("GEN 1"), oldId("GEN 2")], secondsBefore: 0 } } };
  legacyStates.push(open);
}
const legacy = legacyStates.map((state) => {
  const date = L.addDays(state.config.start, 2);
  const prepared = strip(JSON.parse(JSON.stringify(L.prepareState(state, date))));
  const restored = [1, 2, 3, 4, 5].map((version) => {
    try {
      return strip(L.parseBackup(JSON.stringify({ app: "leseweg", version, exportedAt: new Date(legacyAt).toISOString(), theme: "light", state })).state);
    } catch {
      return null;
    }
  });
  return { state, date, prepared, restored };
});

await mkdir("bibelschul_app/test/fixtures", { recursive: true });
await writeFile("bibelschul_app/test/fixtures/parity.json", JSON.stringify({ orders, plans, bible52, durations, zoned, times, scenarios, backups, legacy }));
const steps = scenarios.reduce((n, s) => n + s.steps.length, 0);
console.log(`orders ${Object.keys(orders).length}, plans ${plans.length}, scenarios ${scenarios.length} (${steps} steps, ${scenarios.reduce((n, s) => n + s.steps.filter((x) => x.error).length, 0)} rejected), backups ${backups.length} (${backups.filter((b) => b.ok).length} valid)`);
