import assert from "node:assert/strict";
import { build } from "esbuild";
import "fake-indexeddb/auto";
// The plan below starts on a fixed date; freeze "today" to that start day so the
// test does not depend on the day it runs.
const RealDate = Date;
const fixedNow = RealDate.parse("2026-10-06T10:00:00Z");
globalThis.Date = class extends RealDate {
  constructor(...args) {
    super(...(args.length ? args : [fixedNow]));
  }
  static now() {
    return fixedNow;
  }
};
import { IDBFactory, IDBObjectStore } from "fake-indexeddb";
await build({
  entryPoints: ["lib/local-storage.ts", "lib/actions.ts", "lib/backup.ts"],
  outdir: ".test-runtime",
  bundle: true,
  platform: "node",
  format: "esm",
});
const { readState, changeState, restoreState } = await import(
  "../.test-runtime/local-storage.js"
);
const { applyAction } = await import("../.test-runtime/actions.js");
const { makeBackup, parseBackup } = await import("../.test-runtime/backup.js");
const config = {
  amount: 12,
  unit: "months",
  start: "2026-10-06",
  time: "07:30",
  timezone: "Europe/Berlin",
};
assert.equal(await readState(), null);
let state = await changeState({
  action: "create",
  config,
  lang: "de",
  planId: null,
  opId: crypto.randomUUID(),
});
const op = (fields) => ({
  ...fields,
  planId: state.id,
  opId: crypto.randomUUID(),
});

// Independent transactions from concurrent windows must merge progress.
await Promise.all(
  [0, 1, 2, 3].map((chapter) =>
    changeState(op({ action: "chapter", chapter, done: true })),
  ),
);
state = await readState();
assert.deepEqual(Object.keys(state.done), ["0", "1", "2", "3"]);
const start = op({ action: "timer", mode: "start", day: 0 });
await changeState(start);
const started = await readState();
await changeState(start);
assert.deepEqual(
  (await readState()).timer,
  started.timer,
  "Retry cannot restart a timer",
);
await assert.rejects(
  changeState(op({ action: "timer", mode: "start", day: 1 })),
  /timer/,
);
assert.equal((await readState()).timer.day, 0);

// A resumed app derives time from the stored timestamp, without background JS.
const resumed = applyAction(
  started,
  op({ action: "timer", mode: "pause", day: 0 }),
  started.timer.startedAt + 75000,
);
assert.equal(resumed.timer, null);
assert.equal(resumed.logs.at(-1).seconds, 75);
assert.equal(started.timer.day, 0, "Reducer does not alter the stored input");
const raw = makeBackup(started, "ru", "dark", started.timer.startedAt + 125000);
const backup = parseBackup(raw);
assert.equal(backup.state.logs.at(-1).seconds, 125);
assert.equal(backup.state.timer, null);
assert.equal(backup.state.lang, "ru");
await restoreState(backup.state, state.id);
const restored = await readState();
assert.notEqual(
  restored.id,
  state.id,
  "Restoring invalidates writes from stale windows",
);
assert.deepEqual(restored.done, started.done);
await assert.rejects(
  changeState(op({ action: "chapter", chapter: 8, done: true })),
  /stale/,
);

for (const mutate of [
  (b) => {
    b.version = 9;
  },
  (b) => {
    b.state.config.start = "2026-02-30";
  },
  (b) => {
    b.state.done[1189] = "2026-10-06";
  },
  (b) => {
    b.state.done[0] = "2026-02-30";
  },
  (b) => {
    b.state.logs[0].day = 3649;
  },
  (b) => {
    b.state.logs[0].seconds = -1;
  },
  (b) => {
    b.state.timer = { day: 0, startedAt: Date.now() };
  },
  (b) => {
    b.state.config.timezone = "Unknown/Timezone";
  },
]) {
  const broken = JSON.parse(raw);
  mutate(broken);
  assert.throws(() => parseBackup(JSON.stringify(broken)));
}
assert.throws(() => parseBackup('{"state":'));
assert.deepEqual(
  await readState(),
  restored,
  "Rejected files cannot alter stored data",
);

const put = IDBObjectStore.prototype.put;
IDBObjectStore.prototype.put = () => {
  throw new DOMException("Full", "QuotaExceededError");
};
await assert.rejects(
  changeState({
    action: "chapter",
    chapter: 7,
    done: true,
    planId: restored.id,
    opId: crypto.randomUUID(),
  }),
  /Full/,
);
IDBObjectStore.prototype.put = put;
assert.deepEqual(
  await readState(),
  restored,
  "Failed writes roll back without losing the plan",
);

const firstDevice = indexedDB;
globalThis.indexedDB = new IDBFactory();
assert.equal(
  await readState(),
  null,
  "A separate browser/device starts with no reading data",
);
await restoreState(backup.state, null);
assert.deepEqual((await readState()).done, restored.done);
globalThis.indexedDB = firstDevice;
assert.deepEqual(await readState(), restored);
console.log(
  "Local storage: concurrency, persisted timer, rollback, backup validation and separate devices passed.",
);
