// Port of lib/deadline.ts.
import 'dart:collection';
import 'dart:math';

import 'adaptive.dart';
import 'planner.dart';
import 'state.dart';
import 'util.dart';

/// Both start and deadline are reading days. Calendar arithmetic is independent of DST.
Config planEndingOn(Config config, String end) {
  if (isBible52(config) || !isValidIsoDate(end)) throw const AppError('invalid');
  final next = config.copy()
    ..unit = 'days'
    ..amount = daysBetween(config.start, end) + 1;
  duration(next);
  return next;
}

class DeadlineBounds {
  final String min;
  final String max;
  const DeadlineBounds(this.min, this.max);
}

DeadlineBounds deadlineBounds(ReadingState state, [String? date]) {
  final d = date ?? today(state.config.timezone);
  // A corrected future measurement must not be cut off by shortening the plan.
  final lastRecorded = [
    0,
    ...state.logs.map((l) => l.day),
    ...(state.sessions ?? <Session>[]).map((s) => s.day),
    ...(state.pace?.samples ?? <PaceSample>[]).map((s) => s.day),
    ...?state.adaptive?.finished,
    ...state.done.keys.map((id) => completionDay(state, id)),
    state.timer?.day ?? 0,
    state.pace?.draft?.day ?? 0,
  ].reduce(max);
  final recorded = addDays(state.config.start, lastRecorded);
  return DeadlineBounds(
      d.compareTo(recorded) >= 0 ? d : recorded, addDays(state.config.start, 3649));
}

/// Shared by the action and its preview; no progress, sessions or times are discarded.
ReadingState rescheduleDeadline(ReadingState state, String end, [String? date]) {
  final d = date ?? today(state.config.timezone);
  if (isBible52(state.config)) throw const AppError('invalid');
  if (state.timer != null) throw const AppError('timer');
  final next = prepareState(state, d).copy();
  final bounds = deadlineBounds(next, d);
  if (end.compareTo(bounds.min) < 0 || end.compareTo(bounds.max) > 0) throw const AppError('invalid');
  final config = planEndingOn(next.config, end);
  next.completionDays = SplayTreeMap.of({for (final id in next.done.keys) id: completionDay(next, id)});
  next.config = config;
  final current = dayIndex(config, d);
  final remaining = orderedChapters(config)
      .any((c) => !next.done.containsKey(c.id) && !(next.previouslyRead?.contains(c.id) ?? false));
  // Choosing today explicitly opens today again if unfinished chapters remain.
  // Earlier sessions and their times stay recorded, with no fabricated completion.
  if (end == d && remaining) {
    next.adaptive!.finished = next.adaptive!.finished.where((day) => day != current).toList();
  }
  redistribute(next, current + (next.adaptive!.finished.contains(current) ? 1 : 0), d);
  return next;
}
