// Port of lib/reading-time.ts.
import 'dart:math';

import 'adaptive.dart';
import 'languages.dart';
import 'pace.dart';
import 'planner.dart';
import 'session_stats.dart';
import 'state.dart';
import 'util.dart';

const _units = {
  Lang.de: ('Std.', 'Min.'),
  Lang.en: ('h', 'min'),
  Lang.ru: ('ч', 'мин'),
  Lang.uk: ('год', 'хв'),
};

/// Round only for presentation, after all second-based calculations and sums.
String readingTime(num seconds, Lang lang) {
  final value = seconds.isFinite ? max(0, seconds) : 0;
  final (hour, minute) = _units[lang]!;
  if (value > 0 && value < 60) return '< 1 $minute';
  final minutes = jsRound(value / 60);
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '$h $hour $m $minute' : '$m $minute';
}

/// Compact chart labels; always hours:minutes, never minutes:seconds.
String readingTimeClock(num seconds) {
  final minutes = jsRound(max(0, seconds) / 60);
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

int? correctionSeconds({required String hours, required String minutes, required String seconds}) {
  final digits = RegExp(r'^\d+$');
  if (![hours, minutes, seconds].every(digits.hasMatch)) return null;
  final h = int.parse(hours), m = int.parse(minutes), s = int.parse(seconds);
  final total = h * 3600 + m * 60 + s;
  return h <= 24 && m <= 59 && s <= 59 && total <= 86400 ? total : null;
}

class ReadingTimeSummary {
  final int measuredSeconds;
  final double previousSeconds;
  final double unmeasuredSeconds;
  final double pastSeconds;
  final double remainingSeconds;
  final double totalSeconds;
  final int previousChapters;
  final int unmeasuredChapters;
  final int remainingChapters;
  const ReadingTimeSummary(this.measuredSeconds, this.previousSeconds, this.unmeasuredSeconds, this.pastSeconds,
      this.remainingSeconds, this.totalSeconds, this.previousChapters, this.unmeasuredChapters, this.remainingChapters);
}

ReadingTimeSummary readingTimeSummary(ReadingState state, [int? now, ReadingPace? pace]) {
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final p = pace ?? readingPace(state);
  final inventory = scopeFor(state.config);
  final previous = (state.previouslyRead ?? []).toSet();
  final sessions = sessionsFor(state), measurements = paceState(state);
  // Excluded pace samples still represent real measured time. Never estimate
  // those chapters a second time merely because they do not train the forecast.
  final measured = <int>{
    for (final s in sessions)
      if (s.seconds > 0) ...s.chapters,
    for (final s in measurements.samples)
      if (s.seconds > 0) ...s.chapters,
  };
  final draft = measurements.draft;
  if (draft != null && daySeconds(state, draft.day, n) > draft.secondsBefore) {
    final before = draft.before.toSet();
    for (final id in state.done.keys) {
      if (!before.contains(id)) measured.add(id);
    }
  }
  // Old daily totals have no per-session chapter lists. Keep their measured
  // coverage when there is no newer session/draft describing that day.
  final describedDays = {
    ...sessions.map((s) => s.day),
    ...measurements.samples.map((s) => s.day),
    if (draft != null) draft.day,
  };
  for (final c in inventory) {
    if (state.done.containsKey(c.id)) {
      final day = completionDay(state, c.id);
      if (!describedDays.contains(day) && daySeconds(state, day, n) > 0) measured.add(c.id);
    }
  }
  final previousChapters = inventory.where((c) => previous.contains(c.id)).toList();
  final unmeasured = inventory
      .where((c) => state.done.containsKey(c.id) && !previous.contains(c.id) && !measured.contains(c.id))
      .toList();
  final remaining = inventory.where((c) => !previous.contains(c.id) && !state.done.containsKey(c.id)).toList();
  double estimate(List<Chapter> cs) => estimatedSeconds(cs.fold<int>(0, (s, c) => s + c.words), p);
  final int measuredSeconds = state.logs.fold<int>(0, (s, l) => s + l.seconds) +
      (state.timer != null ? max(0, ((n - state.timer!.startedAt) / 1000).floor()) : 0);
  final previousSeconds = estimate(previousChapters);
  final unmeasuredSeconds = estimate(unmeasured);
  final remainingSeconds = estimate(remaining);
  final pastSeconds = measuredSeconds + previousSeconds + unmeasuredSeconds;
  return ReadingTimeSummary(measuredSeconds, previousSeconds, unmeasuredSeconds, pastSeconds, remainingSeconds,
      pastSeconds + remainingSeconds, previousChapters.length, unmeasured.length, remaining.length);
}
