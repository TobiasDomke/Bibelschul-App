import '../core/insights.dart';
import '../core/pace.dart';
import '../core/state.dart';
import '../core/util.dart';

/// Days in a row with reading, ending today – or yesterday while today is
/// still open, so a streak does not look broken in the morning.
int readingStreak(ReadingState state, String today) {
  var day = readOn(state, today) ? today : addDays(today, -1);
  var count = 0;
  while (readOn(state, day) && count < 10000) {
    count++;
    day = addDays(day, -1);
  }
  return count;
}

/// Chapters checked in the seven days up to and including [today].
int chaptersThisWeek(ReadingState state, String today) {
  final from = addDays(today, -6);
  return state.done.values.where((d) => d.compareTo(from) >= 0 && d.compareTo(today) <= 0).length;
}

/// Latest day with a checked chapter or saved session.
String? lastReadDate(ReadingState state) {
  String? last;
  for (final d in [...state.done.values, ...?state.sessions?.map((s) => s.date)]) {
    if (last == null || d.compareTo(last) > 0) last = d;
  }
  return last;
}

/// Reading speed in words per minute, measured with the timer (recent
/// sessions count more). Word counts come from the Luther 1912 text, so this
/// is a comparable approximation rather than an exact figure for every edition.
int? wordsPerMinute(ReadingPace pace) => pace.wordsPerMinute;
