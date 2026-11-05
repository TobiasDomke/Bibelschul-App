// Port of lib/pace.ts.
import 'dart:math';

import 'adaptive.dart';
import 'difficulty.dart';
import 'planner.dart';
import 'state.dart';
import 'util.dart';

int _savedSeconds(ReadingState state, int day) =>
    state.logs.where((l) => l.day == day).fold(0, (sum, l) => sum + l.seconds);
List<int> _doneIds(ReadingState state) => state.done.keys.toList();

// Old installations have daily totals only. Reuse completed, timed days, and
// keep any open measurement pending until the user finishes it.
PaceState paceState(ReadingState state) {
  if (state.pace != null) return state.pace!;
  final finished = state.adaptive?.finished ??
      [
        for (final day in createPlan(state.config, state.previouslyRead ?? []))
          if (day.chapters.isNotEmpty && day.chapters.every((c) => state.done.containsKey(c.id))) day.index,
      ];
  final samples = <PaceSample>[];
  for (final day in {...finished}) {
    if (state.timer?.day == day) continue;
    final sample = PaceSample(
        day: day, chapters: [for (final c in readChaptersOnDay(state, day)) c.id], seconds: _savedSeconds(state, day));
    if (sample.seconds > 0 && sample.chapters.isNotEmpty) samples.add(sample);
  }
  final day = state.timer?.day ?? dayIndex(state.config, state.adaptive?.date ?? state.config.start);
  final open = !finished.contains(day) && (state.timer?.day == day || _savedSeconds(state, day) > 0);
  final read = {for (final c in readChaptersOnDay(state, day)) c.id};
  return PaceState(
    samples: samples,
    draft: open
        ? PaceDraft(day: day, before: _doneIds(state).where((id) => !read.contains(id)).toList(), secondsBefore: 0)
        : null,
  );
}

void startPace(ReadingState state, int day) {
  final pace = state.pace!;
  if (pace.draft?.day == day) return; // Pause/resume keeps the same measurement.
  pace.draft = PaceDraft(day: day, before: _doneIds(state), secondsBefore: _savedSeconds(state, day));
}

void finishPace(ReadingState state, int finishedDay, [String? review]) {
  final pace = state.pace!;
  final draft = pace.draft;
  if (draft == null || draft.day > finishedDay) return;
  final day = draft.day;
  final before = draft.before.toSet();
  if (draft.manual == true) pace.samples = pace.samples.where((s) => s.day != day).toList();
  final used = {for (final s in pace.samples) ...s.chapters};
  // Finishing a stopped timer after midnight can use its saved measurement.
  // Later untimed reading on another date must not get paired with that time.
  final measuredDates = [
    for (final l in state.logs)
      if (l.day == day) today(state.config.timezone, DateTime.parse(l.at).millisecondsSinceEpoch),
  ]..sort();
  final lastMeasuredDate = measuredDates.isEmpty ? null : measuredDates.last;
  final ids = _doneIds(state)
      .where((id) =>
          !before.contains(id) &&
          (!isBible52(state.config) || bible52ChapterUnit[id] == day) &&
          !used.contains(id) &&
          (day == finishedDay || (lastMeasuredDate != null && state.done[id]!.compareTo(lastMeasuredDate) <= 0)))
      .toList();
  final seconds = _savedSeconds(state, day) - draft.secondsBefore;
  if (ids.isNotEmpty && seconds > 0) {
    pace.samples.add(PaceSample(day: day, chapters: ids, seconds: seconds, review: review));
  }
  pace.draft = null;
}

void correctPace(ReadingState state, int day) {
  final pace = state.pace!;
  // A manual daily total explicitly measures all chapters read in that unit.
  // Include an existing sample's chapters when the timer crossed midnight.
  final measured = {
    for (final c in readChaptersOnDay(state, day)) c.id,
    for (final s in pace.samples)
      if (s.day == day) ...s.chapters,
    if (pace.draft?.day == day) ..._doneIds(state).where((id) => !pace.draft!.before.contains(id)),
  };
  final before = _doneIds(state).where((id) => !measured.contains(id)).toList();
  final draft = PaceDraft(day: day, before: before, secondsBefore: 0, manual: true);
  final closed = (state.adaptive?.finished.contains(day) ?? false) ||
      (!isBible52(state.config) &&
          pace.draft?.day != day &&
          day < dayIndex(state.config, state.adaptive?.date ?? state.config.start));
  if (closed) {
    final pending = pace.draft;
    pace.draft = draft;
    finishPace(state, day);
    pace.draft = pending;
  } else {
    pace.draft = draft;
  }
}

void forgetPaceChapter(ReadingState state, int chapter) {
  // Its time cannot be split reliably: discard the entire affected sample.
  state.pace!.samples = state.pace!.samples.where((s) => !s.chapters.contains(chapter)).toList();
}

bool sampleNeedsReview(PaceSample sample, ReadingState state, [double? baseline]) {
  final base = baseline ?? defaultSecondsPerEffort;
  final cs = chaptersFor(state.config.edition);
  final effort = sample.chapters.fold<int>(0, (n, id) => n + (id >= 0 && id < cs.length ? cs[id].effort : 0));
  if (effort == 0 || sample.seconds == 0) return false;
  final rate = sample.seconds / effort;
  // Legacy: only below 0.05 s per word (1,200 wpm) counted as too fast.
  // Now: three times faster than usual (about 400 wpm at the default pace) is
  // skimming or checking without reading, and is asked about.
  final fast = legacyReadingModel ? min(base / 3, 0.05) : base / 3;
  return sample.seconds > 14400 || rate > max(3 * base, 2) || rate < fast;
}

class ReadingPace {
  final bool personal;
  final bool learning;
  final int samples;
  final int excluded;

  /// Seconds per effort unit (per word in the legacy model).
  final double secondsPerWord;
  final int chapters;
  final int seconds;

  /// Personal correction per kind of text (1 = as expected), learned from
  /// sessions that were mostly one kind of text.
  final Map<String, double> kindFactors;

  /// Measured words per minute (plain words), once the pace is personal.
  final int? wordsPerMinute;
  const ReadingPace(
      this.personal, this.learning, this.samples, this.excluded, this.secondsPerWord, this.chapters, this.seconds,
      [this.kindFactors = const {}, this.wordsPerMinute]);

  double factorFor(Chapter c) => kindFactors[textKind(c.code, c.number)] ?? 1;
}

/// Recent sessions count more: a session [halfLife] sessions ago has half the
/// weight of the latest. Reading speed changes over a year (practice, harder
/// or easier books), and recent sessions are usually of similar text.
const double paceHalfLife = 8;

ReadingPace readingPace(ReadingState? state) {
  final cs = chaptersFor(state?.config.edition);
  final base = defaultSecondsPerEffort;
  final accepted = <PaceSample>[];
  var excluded = 0;
  int effortOf(Iterable<int> ids) => ids.fold<int>(0, (n, id) => n + cs[id].effort);
  for (final sample in state != null ? paceState(state).samples : const <PaceSample>[]) {
    if (sample.seconds <= 0 ||
        sample.chapters.isEmpty ||
        !sample.chapters.every((id) => state!.done.containsKey(id) && id >= 0 && id < cs.length)) {
      continue;
    }
    final priorEffort = effortOf(accepted.expand((s) => s.chapters));
    final baseline = accepted.length >= 3 ? accepted.fold<int>(0, (n, s) => n + s.seconds) / priorEffort : base;
    if (sample.review == 'excluded' || (sample.review != 'confirmed' && sampleNeedsReview(sample, state!, baseline))) {
      excluded++;
      continue;
    }
    accepted.add(sample);
  }
  final seconds = accepted.fold<int>(0, (n, s) => n + s.seconds);
  final ids = accepted.expand((s) => s.chapters).toList();
  final effort = effortOf(ids);
  final confidence = min(1.0, min(accepted.length / 5, effort / 2500));
  if (effort == 0) return ReadingPace(false, false, 0, excluded, base, 0, 0);

  // Recency-weighted personal rate (the legacy model weighs all sessions alike).
  final n = accepted.length;
  double weight(int i) => legacyReadingModel ? 1 : pow(0.5, (n - 1 - i) / paceHalfLife).toDouble();
  var wSeconds = 0.0, wEffort = 0.0, wWords = 0.0;
  for (final (i, s) in accepted.indexed) {
    final w = weight(i);
    wSeconds += w * s.seconds;
    wEffort += w * effortOf(s.chapters);
    wWords += w * s.chapters.fold<int>(0, (t, id) => t + cs[id].words);
  }
  final personalRate = wSeconds / wEffort;

  // Kinds of text the reader is faster or slower with than expected. Only
  // sessions that were mostly one kind count; few sessions move the factor
  // only a little towards what was measured.
  final kinds = <String, (double, double, int)>{};
  if (!legacyReadingModel) {
    for (final (i, s) in accepted.indexed) {
      final byKind = <String, int>{};
      for (final id in s.chapters) {
        final c = cs[id];
        byKind.update(textKind(c.code, c.number), (v) => v + c.effort, ifAbsent: () => c.effort);
      }
      final total = byKind.values.fold<int>(0, (a, b) => a + b);
      final top = byKind.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (total == 0 || top.value / total < 0.7) continue;
      final ratio = (s.seconds / total) / personalRate;
      final w = weight(i) * total;
      final (sum, weights, count) = kinds[top.key] ?? (0.0, 0.0, 0);
      kinds[top.key] = (sum + ratio * w, weights + w, count + 1);
    }
  }
  final kindFactors = {
    for (final MapEntry(key: kind, value: (sum, weights, count)) in kinds.entries)
      kind: (1 + (sum / weights - 1) * count / (count + 3)).clamp(0.6, 1.6).toDouble(),
  };
  return ReadingPace(
    confidence == 1,
    confidence > 0 && confidence < 1,
    accepted.length,
    excluded,
    base * (1 - confidence) + personalRate * confidence,
    ids.length,
    seconds,
    confidence == 1 ? kindFactors : const {},
    confidence == 1 && wWords > 0 ? min(2000, max(1, (60 * wWords / wSeconds).round())) : null,
  );
}

double estimatedSeconds(num effort, ReadingPace pace) => max(0, effort) * pace.secondsPerWord;

/// Estimate for concrete chapters: effort, the reader's pace and their
/// personal factor for each kind of text.
double chaptersSeconds(Iterable<Chapter> chapters, ReadingPace pace) =>
    chapters.fold<double>(0, (s, c) => s + c.effort * pace.secondsPerWord * pace.factorFor(c));

int estimatedMinutes(num words, ReadingPace pace) =>
    words > 0 ? max(1, jsRound(estimatedSeconds(words, pace) / 60)) : 0;
