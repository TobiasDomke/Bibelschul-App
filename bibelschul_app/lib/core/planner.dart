// Port of lib/planner.ts.
import 'dart:math';

import 'book_order.dart';
import 'data.g.dart';
import 'difficulty.dart';
import 'editions.dart';
import 'reading_order.dart';
import 'state.dart';
import 'util.dart';

class Chapter {
  final int id;
  final int bookIndex;
  final String book;
  final String code;
  final int number;
  final int words;

  /// Reading effort: words weighted by the kind of text (difficulty.dart).
  /// Plans are balanced and reading time is estimated by effort.
  final int effort;
  Chapter(this.id, this.bookIndex, this.book, this.code, this.number, this.words)
      : effort = chapterEffort(code, number, words);
}

class Day {
  final int index;
  final String date;
  final List<Chapter> chapters;
  /// Reading effort of the day (sum of the chapters' effort; equals the word
  /// count in the legacy model). Kept under this name for parity with the web app.
  int words;
  Day(this.index, this.date, this.chapters, this.words);
}

List<Chapter> _buildSchlachter() {
  final result = <Chapter>[];
  for (final (bookIndex, b) in bibleBooks.indexed) {
    for (final (i, words) in b.words.indexed) {
      result.add(Chapter(result.length, bookIndex, b.name, b.code, i + 1, words));
    }
  }
  return result;
}

final List<Chapter> chapters = () {
  // This independent inventory was checked book by book against the publisher's
  // chapter headings. A correct grand total alone cannot detect swapped counts.
  assertCanonInventory([for (final b in bibleBooks) (b.code, b.words)]);
  return _buildSchlachter();
}();

void assertCanonInventory(List<(String, List<int>)> inventory) {
  if (inventory.length != schlachterCanon.length ||
      schlachterCanon.indexed.any((e) {
        final (index, (code, count)) = e;
        final item = inventory[index];
        return item.$1 != code || item.$2.length != count || item.$2.any((w) => w <= 0);
      })) {
    throw const AppError('canon');
  }
}

final Map<String, List<Chapter>> _editionChapters = {};

List<Chapter> chaptersFor([String? edition]) {
  final e = edition ?? 'schlachter2000';
  if (e == 'schlachter2000') return chapters;
  final cached = _editionChapters[e];
  if (cached != null) return cached;
  final counts = editionChapterCounts[e]!;
  final result = <Chapter>[];
  for (final (bookIndex, book) in bibleBooks.indexed) {
    for (var i = 0; i < counts[bookIndex]; i++) {
      final weight =
          sourceParts(e, book.code, i + 1).fold<double>(0, (sum, p) => sum + book.words[p.$1 - 1] * p.$2);
      result.add(Chapter(result.length, bookIndex, book.name, book.code, i + 1, max(1, jsRound(weight))));
    }
  }
  if (result.length != 1189) throw const AppError('edition');
  _editionChapters[e] = result;
  return result;
}

// Convert editorial content links, never numeric chapter IDs, between editions.
List<Chapter> _mapEditorial(List<Chapter> items, String? edition) {
  if (edition == null || edition == 'schlachter2000') return items;
  final candidates = chaptersFor(edition);
  final used = <int>{};
  final result = <Chapter>[];
  for (final source in items) {
    for (final c in candidates) {
      if (c.code == source.code && sourceParts(edition, c.code, c.number).any((p) => p.$1 == source.number)) {
        if (used.add(c.id)) result.add(c);
      }
    }
  }
  return result;
}

final int totalWords = chapters.fold(0, (sum, c) => sum + c.words);

int minutes(int words) => max(1, jsRound(words * defaultSecondsPerEffort / 60));

bool isBible52(Config config) => config.template == 'bible52';

Config bible52Config(Config config) => config.copy()
  ..template = 'bible52'
  ..edition = 'schlachter2000'
  ..amount = 52
  ..unit = 'weeks'
  ..scope = 'bible'
  ..order = 'canonical'
  ..keepTogether = false
  ..bookOrder = 'western'
  ..bookOrderMode = 'manual';

int duration(Config config) {
  if (isBible52(config) &&
      (config.edition != 'schlachter2000' ||
          config.amount != 52 ||
          config.unit != 'weeks' ||
          config.scope != 'bible' ||
          config.order != 'canonical' ||
          config.bookOrder != 'western' ||
          config.bookOrderMode != 'manual' ||
          config.keepTogether == true)) {
    throw const AppError('template');
  }
  if (config.amount < 1 || config.amount > 3650) throw const AppError('amount');
  if (!isValidIsoDate(config.start)) throw const AppError('date');
  if (config.start.compareTo('2020-01-01') < 0 || config.start.compareTo('2100-12-31') > 0) {
    throw const AppError('date');
  }
  if (!['days', 'weeks', 'months'].contains(config.unit)) throw const AppError('unit');
  var days = config.amount * (config.unit == 'weeks' ? 7 : 1);
  if (config.unit == 'months') {
    final start = dateAt(config.start);
    final first = DateTime.utc(start.year, start.month + config.amount, 1, 12);
    final last = DateTime.utc(first.year, first.month + 1, 0).day;
    final end = DateTime.utc(first.year, first.month, min(start.day, last), 12);
    days = jsRound(end.difference(start).inMilliseconds / 86400000);
  }
  if (days > 3650 || days < 1) throw const AppError('duration');
  return days;
}

List<Chapter> scopeChapters({String? scope, String? bookOrder, String? edition}) => sortByBookOrder(
      chaptersFor(edition)
          .where((c) => scope == 'ot'
              ? c.bookIndex < 39
              : scope == 'nt'
                  ? c.bookIndex >= 39
                  : true)
          .toList(),
      bookOrder,
      (c) => c.code,
      (c) => c.number,
    );

List<Chapter> scopeFor(Config c) => scopeChapters(scope: c.scope, bookOrder: c.bookOrder, edition: c.edition);

List<Chapter> referenceChapters(String refs) {
  final result = <Chapter>[];
  for (final part in refs.split(';')) {
    final pieces = part.trim().split(RegExp(r'\s+'));
    if (pieces.length < 2) throw const AppError('reference');
    final code = pieces[0];
    for (final range in pieces[1].split(',')) {
      final bounds = range.split('-').map(int.parse).toList();
      final first = bounds[0], last = bounds.length > 1 ? bounds[1] : bounds[0];
      final found = chapters.where((c) => c.code == code && c.number >= first && c.number <= last).toList();
      if (found.length != last - first + 1 || first < 1) throw const AppError('reference');
      result.addAll(found);
    }
  }
  return result;
}

class HistoricalGroup {
  final int id;
  final String refs;
  final String? kind;
  final List<Chapter> chapters;
  const HistoricalGroup(this.id, this.refs, this.kind, this.chapters);
}

final List<HistoricalGroup> historicalGroups = () {
  final groups = [
    for (final (index, block) in chronologicalBlocks.indexed)
      HistoricalGroup(index, block.refs, block.kind, referenceChapters(block.refs)),
  ];
  assertCoverage(chapters, [for (final g in groups) for (final c in g.chapters) c.id]);
  return groups;
}();

final Map<String, List<HistoricalGroup>> _historicalCache = {};

List<HistoricalGroup> historicalGroupsFor(String? edition) {
  final e = edition ?? 'schlachter2000';
  if (e == 'schlachter2000') return historicalGroups;
  final cached = _historicalCache[e];
  if (cached != null) return cached;
  final used = <int>{};
  final groups = <HistoricalGroup>[];
  for (final g in historicalGroups) {
    final mapped = _mapEditorial(g.chapters, e).where((c) => used.add(c.id)).toList();
    if (mapped.isNotEmpty) groups.add(HistoricalGroup(g.id, g.refs, g.kind, mapped));
  }
  assertCoverage(chaptersFor(e), [for (final g in groups) for (final c in g.chapters) c.id]);
  _historicalCache[e] = groups;
  return groups;
}

void assertCoverage(List<Chapter> expected, List<int> ids) {
  final wanted = {for (final c in expected) c.id};
  if (ids.length != wanted.length || ids.toSet().length != ids.length || ids.any((id) => !wanted.contains(id))) {
    throw const AppError('coverage');
  }
}

class Bible52Unit {
  final int index;
  final int week;
  final int slot;
  final String ref;
  final String category;
  final List<Chapter> chapters;
  final String label;
  const Bible52Unit(this.index, this.week, this.slot, this.ref, this.category, this.chapters, this.label);
}

// The photographed 52-week template is an immutable partition of Schlachter 2000.
// Whole-book entries are expanded using our independently verified inventory.
final List<List<Bible52Unit>> bible52Weeks = () {
  final weeks = [
    for (final (week, refs) in bible52WeekRefs.indexed)
      [
        for (final (slot, ref) in refs.indexed)
          () {
            final cs = ref.contains(' ') ? referenceChapters(ref) : chapters.where((c) => c.code == ref).toList();
            if (cs.isEmpty) throw const AppError('template');
            return Bible52Unit(week * 7 + slot, week + 1, slot + 1, ref, bible52Categories[slot], cs,
                ref.contains(' ') ? passage(cs) : cs[0].book);
          }(),
      ],
  ];
  if (weeks.length != 52 || weeks.any((w) => w.length != 7)) throw const AppError('template');
  assertCoverage(chapters, [for (final w in weeks) for (final u in w) for (final c in u.chapters) c.id]);
  return weeks;
}();

final List<Bible52Unit> bible52Units = [for (final w in bible52Weeks) ...w];

final Map<int, int> bible52ChapterUnit = {
  for (final u in bible52Units)
    for (final c in u.chapters) c.id: u.index,
};

// Weighted interleaving keeps every stream's internal order and finishes them
// together. It is deterministic, so extra reading follows the same order.
List<Chapter> _mixedChapters(List<Chapter> items) => _interleave([
      items.where((c) => c.bookIndex < 17 || (c.bookIndex >= 22 && c.bookIndex < 39)).toList(),
      items.where((c) => c.bookIndex >= 17 && c.bookIndex < 22).toList(),
      items.where((c) => c.bookIndex >= 39 && c.bookIndex <= 43).toList(),
      items.where((c) => c.bookIndex > 43).toList(),
    ]);

/// "AT & NT parallel": both testaments book by book side by side, so every
/// day has some Old and (while it lasts) some New Testament.
List<Chapter> _parallelChapters(List<Chapter> items) => _interleave([
      items.where((c) => c.bookIndex < 39).toList(),
      items.where((c) => c.bookIndex >= 39).toList(),
    ]);

List<Chapter> _interleave(List<List<Chapter>> lists) {
  final streams = lists.where((s) => s.isNotEmpty).map((s) => _Stream(s)).toList();
  final count = lists.fold<int>(0, (n, s) => n + s.length);
  final result = <Chapter>[];
  while (result.length < count) {
    _Stream? best;
    for (final s in streams) {
      if (s.cursor >= s.items.length) continue;
      if (best == null || s.read / s.total < best.read / best.total) best = s;
    }
    final chapter = best!.items[best.cursor++];
    result.add(chapter);
    best.read += chapter.effort;
  }
  return result;
}

class _Stream {
  final List<Chapter> items;
  int cursor = 0;
  int read = 0;
  final int total;
  _Stream(this.items) : total = items.fold(0, (s, c) => s + c.effort);
}

/// Psalm chapter ids placed after a chapter (Schlachter ids), see psalmAnchors.
final Map<int, List<int>> psalmAnchorMap = () {
  final psalms = chapters.where((c) => c.code == 'PSA').toList();
  final result = <int, List<int>>{};
  final seen = <int>{};
  for (final (ref, numbers) in psalmAnchors) {
    final anchor = referenceChapters(ref).single;
    for (final n in numbers) {
      if (!seen.add(n)) throw const AppError('psalms');
      (result[anchor.id] ??= []).add(psalms[n - 1].id);
    }
  }
  return result;
}();

class _PsalmOrder {
  const _PsalmOrder(this.order, this.companions, this.groups, this.anchors);
  final List<Chapter> order;

  /// Psalms read alongside, not tied to an event.
  final Set<int> companions;

  /// Historical blocks including their psalms (for keeping text together).
  final List<List<Chapter>> groups;

  /// Psalm id -> the chapter it belongs to.
  final Map<int, Chapter> anchors;
}

final Map<String, _PsalmOrder> _psalmOrderCache = {};

/// "Chronologisch mit Psalmen": the chronological order without its psalm
/// blocks; each psalm with a known occasion follows that chapter, all other
/// psalms are spread evenly over the plan.
_PsalmOrder _psalmOrder(Config config) {
  final edition = config.edition ?? 'schlachter2000';
  final scope = config.scope ?? 'bible';
  return _psalmOrderCache['$edition:$scope'] ??= () {
    bool inScope(Chapter c) => scope == 'ot' ? c.bookIndex < 39 : (scope == 'nt' ? c.bookIndex >= 39 : true);
    final units = <List<Chapter>>[];
    final groups = <List<Chapter>>[];
    for (final g in historicalGroups) {
      final group = <Chapter>[];
      for (final c in g.chapters) {
        if (c.code == 'PSA' || !inScope(c)) continue;
        final unit = [c, for (final id in psalmAnchorMap[c.id] ?? const <int>[]) if (inScope(chapters[id])) chapters[id]];
        units.add(unit);
        group.addAll(unit);
      }
      if (group.isNotEmpty) groups.add(group);
    }
    final placed = {for (final u in units) for (final c in u) c.id};
    final companions = [for (final c in chapters) if (c.code == 'PSA' && inScope(c) && !placed.contains(c.id)) c];
    final mainTotal = units.fold<int>(0, (n, u) => n + u.fold<int>(0, (m, c) => m + c.effort));
    final companionTotal = companions.fold<int>(0, (n, c) => n + c.effort);
    final order = <Chapter>[];
    var mainRead = 0, companionRead = 0, next = 0;
    for (final unit in units) {
      order.addAll(unit);
      mainRead += unit.fold<int>(0, (m, c) => m + c.effort);
      while (next < companions.length && companionRead / companionTotal < mainRead / mainTotal) {
        companionRead += companions[next].effort;
        order.add(companions[next++]);
      }
    }
    order.addAll(companions.skip(next));
    final anchors = <int, Chapter>{
      for (final u in units)
        for (final p in u.skip(1)) p.id: u.first,
    };
    if (edition == 'schlachter2000') {
      return _PsalmOrder(order, {for (final c in companions) c.id}, groups, anchors);
    }
    final mapped = _mapEditorial(order, edition);
    final ids = {for (final c in mapped) c.id};
    final companionIds = {for (final c in _mapEditorial(companions, edition)) c.id};
    final edited = chaptersFor(edition);
    final mappedAnchors = <int, Chapter>{};
    for (final MapEntry(key: psalm, value: anchor) in anchors.entries) {
      final targets = _mapEditorial([chapters[psalm]], edition);
      final at = _mapEditorial([anchor], edition);
      if (targets.isNotEmpty && at.isNotEmpty) {
        for (final t in targets) {
          mappedAnchors[t.id] = at.first;
        }
      }
    }
    assert(ids.every((id) => id < edited.length));
    return _PsalmOrder(
      mapped,
      companionIds.difference(mappedAnchors.keys.toSet()),
      [for (final g in groups) _mapEditorial(g, edition)],
      mappedAnchors,
    );
  }();
}

/// Companion psalms of a plan: read after the day's main text.
Set<int> companionPsalms(Config config) => config.order == 'chronoPsalms' ? _psalmOrder(config).companions : const {};

/// The chapter a psalm belongs to in "Chronologisch mit Psalmen".
Chapter? psalmAnchor(Config config, int psalm) =>
    config.order == 'chronoPsalms' ? _psalmOrder(config).anchors[psalm] : null;

final Map<String, List<Chapter>> _orderCache = {};

List<Chapter> orderedChapters(Config config) {
  if (isBible52(config)) return [for (final u in bible52Units) ...u.chapters];
  final key =
      '${config.edition ?? 'schlachter2000'}:${config.scope ?? 'bible'}:${config.order ?? 'canonical'}:${config.bookOrder ?? 'western'}';
  return _orderCache[key] ??= _buildOrder(config);
}

List<Chapter> _buildOrder(Config config) {
  final scope = scopeFor(config);
  if (config.order == 'mixed') return _mixedChapters(scope);
  if (config.order == 'parallel') return _parallelChapters(scope);
  if (config.order == 'chronoPsalms') {
    final ids = {for (final c in scope) c.id};
    final order = [for (final c in _psalmOrder(config).order) if (ids.contains(c.id)) c];
    assertCoverage(scope, [for (final c in order) c.id]);
    return order;
  }
  if (config.order == 'chronological') {
    final ids = {for (final c in scope) c.id};
    return [
      for (final g in historicalGroupsFor(config.edition))
        for (final c in g.chapters)
          if (ids.contains(c.id)) c,
    ];
  }
  return scope;
}

final List<List<Chapter>> _cohesiveGroups = cohesiveReferences.map(referenceChapters).toList();
final Map<String, List<List<Chapter>>> _cohesiveCache = {};

typedef Boundary = bool Function(Chapter a, Chapter b);

Boundary? boundaryPreference(Config config) {
  if (config.keepTogether != true) return null;
  final edition = config.edition ?? 'schlachter2000';
  final List<List<Chapter>> groups = config.order == 'chronological'
      ? [for (final g in historicalGroupsFor(config.edition)) g.chapters]
      : config.order == 'chronoPsalms'
          ? _psalmOrder(config).groups
          : (_cohesiveCache[edition] ??= [for (final g in _cohesiveGroups) _mapEditorial(g, config.edition)]);
  final membership = <int, int>{};
  for (final (i, group) in groups.indexed) {
    for (final c in group) {
      membership[c.id] = i;
    }
  }
  return (a, b) => membership[a.id] != membership[b.id] || !membership.containsKey(a.id);
}

List<Day> createPlan(Config config, [List<int> previouslyRead = const []]) {
  final items = orderedChapters(config);
  final previous = previouslyRead.toSet();
  final allowed = {for (final c in items) c.id};
  if (previous.length != previouslyRead.length || previouslyRead.any((id) => !allowed.contains(id))) {
    throw const AppError('prior');
  }
  duration(config);
  final List<Day> plan;
  if (isBible52(config)) {
    plan = [
      for (final u in bible52Units)
        () {
          final cs = u.chapters.where((c) => !previous.contains(c.id)).toList();
          return Day(u.index, addDays(config.start, u.index), cs, cs.fold(0, (n, c) => n + c.effort));
        }(),
    ];
  } else {
    plan = distributePlan(config, items.where((c) => !previous.contains(c.id)).toList(), duration(config), config.start);
  }
  assertCoverage(items, [...previouslyRead, for (final d in plan) for (final c in d.chapters) c.id]);
  return plan;
}

/// Splits [items] (in plan order) into [days] days of about equal effort.
/// "AT & NT parallel" first spreads the New Testament evenly (at most one
/// chapter a day while it is shorter than the plan), then fills every day with
/// Old Testament reading up to the same length.
List<Day> distributePlan(Config config, List<Chapter> items, int days, String start) {
  if (config.order != 'parallel') return distributeChapters(items, days, start, boundaryPreference(config));
  final nt = items.where((c) => c.bookIndex >= 39).toList();
  final ot = items.where((c) => c.bookIndex < 39).toList();
  if (nt.isEmpty || ot.isEmpty || days < 1) return distributeChapters(items, days, start);
  final result = distributeChapters(nt, days, start);
  var remaining = items.fold<int>(0, (n, c) => n + c.effort);
  var cursor = 0;
  for (var i = 0; i < days; i++) {
    final day = result[i];
    final remainingDays = days - i;
    final target = remaining / remainingDays - day.words;
    remaining -= day.words;
    final mustTake = ot.length - cursor >= remainingDays;
    final limit = mustTake ? ot.length - remainingDays + 1 : ot.length;
    var words = 0;
    while (cursor < ot.length) {
      final next = ot[cursor].effort;
      final take = remainingDays == 1 ||
          (words == 0 && mustTake) ||
          (cursor < limit && (words + next - target).abs() <= (words - target).abs());
      if (!take) break;
      day.chapters.add(ot[cursor++]);
      words += next;
    }
    day.words += words;
    remaining -= words;
  }
  return result;
}

List<Day> distributeChapters(List<Chapter> items, int days, String start, [Boundary? preferredBoundary]) {
  if (days < 1) return [];
  final result = [for (var i = 0; i < days; i++) Day(i, addDays(start, i), <Chapter>[], 0)];
  if (days >= items.length) {
    for (final (i, c) in items.indexed) {
      final day = result[(i * days) ~/ items.length];
      day.chapters.add(c);
      day.words += c.effort;
    }
    return result;
  }
  var cursor = 0;
  var remainingWords = items.fold<int>(0, (sum, c) => sum + c.effort);
  for (var i = 0; i < days; i++) {
    final remainingDays = days - i;
    final target = remainingWords / remainingDays;
    final lastExclusive = items.length - remainingDays + 1;
    final day = result[i];
    do {
      final c = items[cursor++];
      day.chapters.add(c);
      day.words += c.effort;
    } while (cursor < lastExclusive &&
        (remainingDays == 1 ||
            (day.words + items[cursor].effort - target).abs() <= (day.words - target).abs()));
    if (preferredBoundary != null && remainingDays > 1) {
      final begin = cursor - day.chapters.length;
      final baseline = (day.words - target).abs();
      var bestEnd = cursor;
      var bestWords = day.words;
      var bestCost = baseline + (preferredBoundary(items[cursor - 1], items[cursor]) ? 0 : target * 0.2);
      var words = 0;
      for (var end = begin + 1; end <= lastExclusive; end++) {
        words += items[end - 1].effort;
        if ((words - target).abs() <= baseline + target * 0.25) {
          final cost = (words - target).abs() + (preferredBoundary(items[end - 1], items[end]) ? 0 : target * 0.2);
          if (cost < bestCost) {
            bestCost = cost;
            bestEnd = end;
            bestWords = words;
          }
        }
        if (words > target + baseline + target * 0.25) break;
      }
      cursor = bestEnd;
      day.chapters
        ..clear()
        ..addAll(items.sublist(begin, cursor));
      day.words = bestWords;
    }
    remainingWords -= day.words;
  }
  return result;
}

String passage(List<Chapter> items, [List<String>? names]) {
  if (items.isEmpty) return '';
  final groups = <String>[];
  for (var i = 0; i < items.length;) {
    var j = i;
    while (j + 1 < items.length && items[j + 1].code == items[i].code && items[j + 1].number == items[j].number + 1) {
      j++;
    }
    groups.add('${names?[items[i].bookIndex] ?? items[i].book} ${items[i].number}${j > i ? '–${items[j].number}' : ''}');
    i = j + 1;
  }
  return groups.join(' · ');
}
