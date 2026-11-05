// Port of lib/edition-migration.ts.
import 'dart:collection';

import 'editions.dart';
import 'planner.dart';
import 'state.dart';

// Printed chapter references in old releases did not identify the reader's
// paper edition. Do not infer that a numbered Psalm means the same content.
// Fully completed books are safe; partial changed books need explicit review.
void changeEdition(ReadingState state, String edition) {
  final from = state.config.edition ?? 'schlachter2000';
  if (from == edition) {
    state.config.edition = edition;
    return;
  }
  final old = chaptersFor(state.config.edition);
  final config = state.config.copy()..edition = edition;
  final target = chaptersFor(edition);
  final byRef = {for (final c in target) '${c.code} ${c.number}': c};
  final affected = <String>{};
  if ((from == 'schlachter2000') != (edition == 'schlachter2000')) affected.addAll(['JOL', 'MAL']);
  if ((from == 'synodal') != (edition == 'synodal')) affected.add('PSA');
  final read = {...?state.previouslyRead, ...state.done.keys};
  final fullBooks = affected.where((code) => old.where((c) => c.code == code).every((c) => read.contains(c.id))).toSet();
  int? mapId(int id) {
    if (id < 0 || id >= old.length) return null;
    final c = old[id];
    return !affected.contains(c.code) ? byRef['${c.code} ${c.number}']?.id : null;
  }

  state.editionReview = [
    ...?state.editionReview,
    for (final c in old)
      if (affected.contains(c.code) && !fullBooks.contains(c.code) && read.contains(c.id))
        '${editions[from]!.name}: ${c.code} ${c.number}',
  ];
  final originalDone = SplayTreeMap<int, String>.of(state.done);
  final fullyPrior =
      fullBooks.where((code) => !old.any((c) => c.code == code && originalDone.containsKey(c.id))).toSet();
  state.previouslyRead = [
    for (final id in state.previouslyRead ?? <int>[])
      if (mapId(id) != null) mapId(id)!,
    for (final c in target)
      if (fullyPrior.contains(c.code)) c.id,
  ];
  final done = SplayTreeMap<int, String>();
  state.done.forEach((id, date) {
    final n = mapId(id);
    if (n != null) done[n] = date;
  });
  state.done = done;
  for (final c in target.where((c) => fullBooks.contains(c.code) && !fullyPrior.contains(c.code))) {
    final dates = [
      for (final o in old)
        if (o.code == c.code && originalDone.containsKey(o.id)) originalDone[o.id]!,
    ]..sort();
    state.done[c.id] = dates.last;
  }
  if (state.completionDays != null) {
    final days = SplayTreeMap<int, int>();
    state.completionDays!.forEach((id, day) {
      final n = mapId(id);
      if (n != null) days[n] = day;
    });
    state.completionDays = days;
  }
  final originalSessions = state.sessions;
  state.sessions = state.sessions
      ?.map((s) => Session(
            id: s.id,
            day: s.day,
            date: s.date,
            seconds: s.seconds,
            chapters: [
              for (final id in s.chapters)
                if ((fullBooks.contains(old[id].code) ? byRef['${old[id].code} ${old[id].number}']?.id : mapId(id))
                    case final n?)
                  n,
            ],
          ))
      .toList();
  for (final code in fullBooks) {
    Session? original;
    for (final s in originalSessions ?? <Session>[]) {
      if (s.chapters.any((id) => old[id].code == code)) {
        original = s;
        break;
      }
    }
    Session? session;
    for (final s in state.sessions ?? <Session>[]) {
      if (s.id == original?.id) {
        session = s;
        break;
      }
    }
    if (session != null) {
      final included = {for (final s in state.sessions!) ...s.chapters};
      session.chapters.addAll([
        for (final c in target)
          if (c.code == code && state.done.containsKey(c.id) && !included.contains(c.id)) c.id,
      ]);
    }
  }
  state.pace = PaceState();
  state.config = config;
  if (config.bookOrderMode == 'auto') state.config.bookOrder = editions[edition]!.order;
  state.pendingBookOrder = null;
  state.adaptive = null;
}
