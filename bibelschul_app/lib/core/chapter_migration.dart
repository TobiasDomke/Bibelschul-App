// Port of lib/chapter-migration.ts.
import 'dart:collection';

import 'data.g.dart';
import 'planner.dart';
import 'state.dart';
import 'util.dart';

// Versions through 1.8.0 used KJV-style counts for Joel/Malachi while displaying
// Schlachter references. Resolve saved IDs by the displayed book/chapter, never
// by their new numeric position. In particular old MAL 4 must not become MAL 3.
final List<String> legacyReferences = [
  for (final (code, count) in schlachterCanon)
    for (var i = 0; i < (code == 'JOL' ? 3 : code == 'MAL' ? 4 : count); i++) '$code ${i + 1}',
];

final Map<String, int> _currentIds = {for (final c in chapters) '${c.code} ${c.number}': c.id};

ReadingState migrateChapters(ReadingState state) {
  if (state.chapterSchema == 2) return state;
  final copy = state.copy();
  String reference(int id) {
    if (id < 0 || id >= legacyReferences.length) throw const AppError('chapter-migration');
    return legacyReferences[id];
  }

  bool affected(int id) => RegExp(r'^(JOL|MAL) ').hasMatch(reference(id));
  int? mapId(int id) => _currentIds[reference(id)];
  List<int> mapIds(List<int> ids) => [
        for (final id in ids)
          if (mapId(id) != null) mapId(id)!,
      ];
  SplayTreeMap<int, T> mapRecord<T>(Map<int, T> values) {
    final result = SplayTreeMap<int, T>();
    values.forEach((id, value) {
      final mapped = mapId(id);
      if (mapped != null) result[mapped] = value;
    });
    return result;
  }

  final previous = [for (final id in state.previouslyRead ?? <int>[]) if (affected(id)) reference(id)];
  final done = <String, String>{
    for (final e in state.done.entries)
      if (affected(e.key)) reference(e.key): e.value,
  };
  final samples = [
    for (final s in state.pace?.samples ?? <PaceSample>[])
      if (s.chapters.any(affected)) CorrectionSample(s.day, s.chapters.map(reference).toList(), s.seconds),
  ];
  if (previous.isNotEmpty || done.isNotEmpty || samples.isNotEmpty) {
    copy.chapterCorrection = ChapterCorrection(previous, done, samples);
  }
  // Very old backups can have daily time totals without chapter/time pairs.
  // If affected chapters were read, do not reconstruct potentially false pairs.
  if (copy.pace == null && done.isNotEmpty) copy.pace = PaceState();
  copy.done = mapRecord(state.done);
  if (state.previouslyRead != null) copy.previouslyRead = mapIds(state.previouslyRead!);
  if (state.completionDays != null) copy.completionDays = mapRecord(state.completionDays!);
  if (copy.pace != null) {
    // The original times remain in logs and the archive. Do not use ambiguous
    // chapter/word pairs as training data for the future reading estimate.
    copy.pace!.samples = [
      for (final s in copy.pace!.samples)
        if (!s.chapters.any(affected))
          PaceSample(day: s.day, chapters: mapIds(s.chapters), seconds: s.seconds, review: s.review),
    ];
    if (copy.pace!.draft != null) {
      final uncertain = state.done.keys.any((id) => affected(id) && !state.pace!.draft!.before.contains(id));
      if (uncertain) {
        copy.pace!.draft = null;
      } else {
        copy.pace!.draft!.before = mapIds(copy.pace!.draft!.before);
      }
    }
  }
  if (copy.adaptive != null) {
    copy.adaptive!.days = copy.adaptive!.days.map(mapIds).toList();
    copy.adaptive!.extra = SplayTreeMap.of(copy.adaptive!.extra.map((day, ids) => MapEntry(day, mapIds(ids))));
    if (copy.adaptive!.unplanned != null) copy.adaptive!.unplanned = mapIds(copy.adaptive!.unplanned!);
  }
  copy.chapterSchema = 2;
  // prepareState redistributes all still unread chapters, including Joel 4.
  return copy;
}
