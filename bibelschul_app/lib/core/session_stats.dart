// Port of lib/session-stats.ts.
import 'dart:math';

import 'state.dart';
import 'util.dart';

String logDate(ReadingState state, TimeLog log) =>
    log.readingDate ?? today(state.config.timezone, DateTime.parse(log.at).millisecondsSinceEpoch);

List<Session> sessionsFor(ReadingState state) {
  if (state.sessions != null) return state.sessions!;
  // Older versions retained daily totals, not session boundaries. Reconstruct
  // known pace samples and one aggregate for each otherwise completed day.
  String firstDate(int day) {
    for (final l in state.logs) {
      if (l.day == day) return l.readingDate ?? addDays(state.config.start, day);
    }
    return addDays(state.config.start, day);
  }

  final samples = state.pace?.samples ?? <PaceSample>[];
  final result = [
    for (final (i, s) in samples.indexed)
      Session(id: 'legacy-$i', day: s.day, date: firstDate(s.day), chapters: s.chapters, seconds: s.seconds),
  ];
  for (final day in state.adaptive?.finished ?? <int>[]) {
    if (!result.any((s) => s.day == day)) {
      result.add(Session(
        id: 'legacy-day-$day',
        day: day,
        date: firstDate(day),
        chapters: state.done.keys.where((id) => state.done[id] == addDays(state.config.start, day)).toList(),
        seconds: state.logs.where((l) => l.day == day).fold(0, (n, l) => n + l.seconds),
      ));
    }
  }
  return result;
}

Map<String, int> dailySeconds(ReadingState state, [int? now]) {
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final values = <String, int>{};
  for (final log in state.logs) {
    final date = logDate(state, log);
    values[date] = (values[date] ?? 0) + log.seconds;
  }
  if (state.timer != null) {
    final date = today(state.config.timezone, state.timer!.startedAt);
    values[date] = (values[date] ?? 0) + max(0, ((n - state.timer!.startedAt) / 1000).floor());
  }
  return values;
}
