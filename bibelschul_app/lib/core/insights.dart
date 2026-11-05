import 'dart:math';

import 'adaptive.dart';
import 'planner.dart';
import 'state.dart';

/// Whether anything was read or a session was saved on [date].
bool readOn(ReadingState state, String date) =>
    state.done.values.contains(date) || (state.sessions ?? const <Session>[]).any((s) => s.date == date);

/// Every chapter of the plan is read (in the app or before the plan).
bool planComplete(ReadingState state) {
  final previous = (state.previouslyRead ?? const <int>[]).toSet();
  return scopeFor(state.config).every((c) => state.done.containsKey(c.id) || previous.contains(c.id));
}

class Behind {
  const Behind(this.chapters, this.days);

  /// Chapters behind the original, evenly weighted plan.
  final int chapters;

  /// Days by which the target would have to move to keep the original daily amount.
  final int days;
}

/// Compares progress with the plan as it was first distributed. Flexible plans
/// already redistribute automatically; this only offers the alternative of
/// moving the target date when the reader falls clearly behind.
Behind? behindSchedule(ReadingState state, String date) {
  if (isBible52(state.config)) return null;
  final original = createPlan(state.config, state.previouslyRead ?? const []);
  final current = dayIndex(state.config, date);
  if (current <= 0 || original.isEmpty) return null;
  final planned = original.fold<int>(0, (n, d) => n + d.chapters.length);
  if (planned == 0) return null;
  final expected = original.take(current).fold<int>(0, (n, d) => n + d.chapters.length);
  final behind = expected - state.done.length;
  final perDay = planned / original.length;
  if (behind < max(3, (perDay * 2).ceil())) return null;
  final days = (behind / perDay).ceil();
  final room = 3649 - (duration(state.config) - 1);
  if (room <= 0) return null;
  return Behind(behind, min(days, room));
}

/// Share of each book that is read, in the plan's book order.
List<(int bookIndex, int read, int total)> bookProgress(ReadingState state) {
  final previous = (state.previouslyRead ?? const <int>[]).toSet();
  final result = <int, (int, int)>{};
  for (final c in scopeFor(state.config)) {
    final (read, total) = result[c.bookIndex] ?? (0, 0);
    final isRead = state.done.containsKey(c.id) || previous.contains(c.id);
    result[c.bookIndex] = (read + (isRead ? 1 : 0), total + 1);
  }
  return [for (final e in result.entries) (e.key, e.value.$1, e.value.$2)];
}

/// Share of each book's text that is read, by words – Psalm 119 weighs far
/// more than Psalm 117, unlike a simple chapter count.
Map<int, double> bookTextShare(ReadingState state) {
  final previous = (state.previouslyRead ?? const <int>[]).toSet();
  final words = <int, (int, int)>{};
  for (final c in scopeFor(state.config)) {
    final (read, total) = words[c.bookIndex] ?? (0, 0);
    final isRead = state.done.containsKey(c.id) || previous.contains(c.id);
    words[c.bookIndex] = (read + (isRead ? c.words : 0), total + c.words);
  }
  return {for (final MapEntry(key: book, value: (read, total)) in words.entries) book: total == 0 ? 0 : read / total};
}
