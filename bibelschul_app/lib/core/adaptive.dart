// Port of lib/adaptive.ts.
import 'dart:collection';
import 'dart:math';

import 'chapter_migration.dart';
import 'planner.dart';
import 'state.dart';
import 'util.dart';

int dayIndex(Config config, String date) =>
    max(0, min(duration(config) - 1, daysBetween(config.start, date)));

int completionDay(ReadingState state, int chapter) {
  if (isBible52(state.config)) return bible52ChapterUnit[chapter]!;
  return state.completionDays?[chapter] ?? dayIndex(state.config, state.done[chapter]!);
}

// Rebuild only recommendations. Historical rows reflect what was actually read,
// never the former recommendation. The original last date is kept exactly.
void redistribute(ReadingState state, int from, String date) {
  if (isBible52(state.config)) {
    final previous = (state.previouslyRead ?? []).toSet();
    final closed = (state.adaptive?.finished ?? []).toSet();
    state.adaptive = Adaptive(
      date: date,
      days: [for (final d in createPlan(state.config, previous.toList())) [for (final c in d.chapters) c.id]],
      finished: [
        for (final u in bible52Units)
          if (u.chapters.every((c) => previous.contains(c.id)) ||
              (closed.contains(u.index) &&
                  u.chapters.every((c) => previous.contains(c.id) || state.done.containsKey(c.id))))
            u.index,
      ],
      extra: SplayTreeMap(),
      unplanned: [],
    );
    return;
  }
  final count = duration(state.config);
  final history = List.generate(count, (_) => <int>[]);
  final ordered = orderedChapters(state.config);
  final previous = (state.previouslyRead ?? []).toSet();
  for (final c in ordered) {
    if (state.done.containsKey(c.id)) history[completionDay(state, c.id)].add(c.id);
  }
  final remaining = ordered.where((c) => !state.done.containsKey(c.id) && !previous.contains(c.id)).toList();
  final future =
      distributeChapters(remaining, count - from, addDays(state.config.start, from), boundaryPreference(state.config));
  assertCoverage(ordered, [
    ...?state.previouslyRead,
    ...state.done.keys,
    ...(from >= count ? remaining.map((c) => c.id) : [for (final d in future) for (final c in d.chapters) c.id]),
  ]);
  final extra = SplayTreeMap<int, List<int>>();
  // Keep chapters already read today visible when returning or continuing.
  if (from < count && history[from].isNotEmpty) extra[from] = history[from];
  state.adaptive = Adaptive(
    date: date,
    unplanned: from >= count ? [for (final c in remaining) c.id] : [],
    days: [
      for (var index = 0; index < count; index++)
        index < from
            ? history[index]
            : (index - from < future.length ? [for (final c in future[index - from].chapters) c.id] : <int>[]),
    ],
    finished: state.adaptive?.finished ?? [],
    extra: extra,
  );
}

ReadingState prepareState(ReadingState state, [String? date]) {
  final d = date ?? today(state.config.timezone);
  if (isBible52(state.config)) {
    final copy = state.copy();
    copy.pendingBookOrder = null;
    redistribute(copy, 0, d);
    return copy;
  }
  final correcting = state.chapterSchema != 2;
  if (correcting) state = migrateChapters(state);
  if (state.adaptive?.date == d && state.pendingBookOrder == null && !correcting) return state;
  // A session spanning midnight keeps its recommendation until it is finished.
  if (state.adaptive != null && state.timer != null && !correcting) return state;
  final copy = state.copy();
  if (copy.pendingBookOrder != null) {
    copy.config.bookOrder = copy.pendingBookOrder;
    copy.pendingBookOrder = null;
  }
  final current = dayIndex(copy.config, d);
  if (copy.adaptive == null) {
    // Preserve completed-unit counts when upgrading a fixed-plan installation.
    copy.adaptive = Adaptive(
      date: d,
      days: [],
      extra: SplayTreeMap(),
      finished: [
        for (final day in createPlan(copy.config, copy.previouslyRead ?? []))
          if (day.date.compareTo(d) <= 0 &&
              day.chapters.isNotEmpty &&
              day.chapters.every((c) => copy.done.containsKey(c.id)))
            day.index,
      ],
    );
  }
  final from = correcting && copy.timer != null
      ? copy.timer!.day
      : copy.adaptive!.finished.contains(current)
          ? current + 1
          : current;
  redistribute(copy, from, d);
  return copy;
}

List<Day> readingPlan(ReadingState state, [String? date]) {
  if (isBible52(state.config)) return createPlan(state.config);
  final prepared = prepareState(state, date ?? today(state.config.timezone));
  final cs = chaptersFor(prepared.config.edition);
  return [
    for (final (index, ids) in prepared.adaptive!.days.indexed)
      Day(index, addDays(state.config.start, index), [for (final id in ids) cs[id]],
          ids.fold(0, (sum, id) => sum + cs[id].effort)),
  ];
}

List<Chapter> sessionChapters(ReadingState state, int day) {
  if (isBible52(state.config)) return day >= 0 && day < bible52Units.length ? bible52Units[day].chapters : [];
  final ids = {
    ...?(day >= 0 && day < (state.adaptive?.days.length ?? 0) ? state.adaptive!.days[day] : null),
    ...?state.adaptive?.extra[day],
  };
  return orderedChapters(state.config).where((c) => ids.contains(c.id)).toList();
}

Chapter? nextExtraChapter(ReadingState state, int day) {
  if (isBible52(state.config)) return null;
  final present = {for (final c in sessionChapters(state, day)) c.id};
  for (final c in orderedChapters(state.config)) {
    if (!state.done.containsKey(c.id) &&
        !(state.previouslyRead?.contains(c.id) ?? false) &&
        !present.contains(c.id)) {
      return c;
    }
  }
  return null;
}

List<Chapter> readChaptersOnDay(ReadingState state, int day) => orderedChapters(state.config)
    .where((c) => state.done.containsKey(c.id) && completionDay(state, c.id) == day)
    .toList();

// Unfinished sessions take precedence over the next template unit, including after pausing.
int bible52CurrentUnit(ReadingState state) {
  if (state.timer != null) return state.timer!.day;
  if (state.pace?.draft != null) return state.pace!.draft!.day;
  for (final u in bible52Units) {
    if (!(state.adaptive?.finished.contains(u.index) ?? false)) return u.index;
  }
  return 363;
}
