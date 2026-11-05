// Port of lib/pace.ts.
import 'dart:math';

import 'adaptive.dart';
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

bool sampleNeedsReview(PaceSample sample, ReadingState state, [double baseline = 60 / 180]) {
  final cs = chaptersFor(state.config.edition);
  final words = sample.chapters.fold<int>(0, (n, id) => n + (id >= 0 && id < cs.length ? cs[id].words : 0));
  if (words == 0 || sample.seconds == 0) return false;
  final rate = sample.seconds / words;
  return sample.seconds > 14400 || rate > max(3 * baseline, 2) || rate < min(baseline / 3, 0.05);
}

class ReadingPace {
  final bool personal;
  final bool learning;
  final int samples;
  final int excluded;
  final double secondsPerWord;
  final int chapters;
  final int seconds;
  const ReadingPace(
      this.personal, this.learning, this.samples, this.excluded, this.secondsPerWord, this.chapters, this.seconds);
}

ReadingPace readingPace(ReadingState? state) {
  final cs = chaptersFor(state?.config.edition);
  final accepted = <PaceSample>[];
  var excluded = 0;
  for (final sample in state != null ? paceState(state).samples : const <PaceSample>[]) {
    if (sample.seconds <= 0 ||
        sample.chapters.isEmpty ||
        !sample.chapters.every((id) => state!.done.containsKey(id) && id >= 0 && id < cs.length)) {
      continue;
    }
    final priorWords = accepted.expand((s) => s.chapters).fold<int>(0, (n, id) => n + cs[id].words);
    final baseline = accepted.length >= 3 ? accepted.fold<int>(0, (n, s) => n + s.seconds) / priorWords : 60 / 180;
    if (sample.review == 'excluded' || (sample.review != 'confirmed' && sampleNeedsReview(sample, state!, baseline))) {
      excluded++;
      continue;
    }
    accepted.add(sample);
  }
  final seconds = accepted.fold<int>(0, (n, s) => n + s.seconds);
  final ids = accepted.expand((s) => s.chapters).toList();
  final words = ids.fold<int>(0, (n, id) => n + cs[id].words);
  final confidence = min(1.0, min(accepted.length / 5, words / 2500));
  return ReadingPace(
    confidence == 1,
    confidence > 0 && confidence < 1,
    accepted.length,
    excluded,
    words > 0 ? (60 / 180) * (1 - confidence) + (seconds / words) * confidence : 60 / 180,
    ids.length,
    seconds,
  );
}

double estimatedSeconds(num words, ReadingPace pace) => max(0, words) * pace.secondsPerWord;

int estimatedMinutes(num words, ReadingPace pace) =>
    words > 0 ? max(1, jsRound(estimatedSeconds(words, pace) / 60)) : 0;
