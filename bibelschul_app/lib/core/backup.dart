// Port of lib/backup.ts. Backups use the web app's format (version 8), so a
// "Leseweg" backup from the browser can be restored here and vice versa.
import 'dart:convert';
import 'dart:math';

import 'actions.dart';
import 'adaptive.dart';
import 'book_order.dart';
import 'languages.dart';
import 'planner.dart';
import 'state.dart';
import 'util.dart';

const maxBackupBytes = 12 * 1024 * 1024;
const _bad = AppError('backup');

class Backup {
  final int version;
  final String exportedAt;
  final String theme;
  final ReadingState state;
  const Backup(this.version, this.exportedAt, this.theme, this.state);
}

void _check(bool ok) {
  if (!ok) throw _bad;
}

Map<String, Object?> _obj(Object? v, List<String> keys) {
  _check(v is Map && v.keys.every((k) => k is String && keys.contains(k)));
  return (v as Map).cast<String, Object?>();
}

bool _isInt(Object? v, int min, int max) => v is num && v == v.roundToDouble() && v >= min && v <= max;
bool _isDate(Object? v) => v is String && isValidIsoDate(v);
bool _isTimestamp(Object? v) => v is String && v.length <= 40 && DateTime.tryParse(v) != null;
bool _intList(Object? v, int maxLen, [int minLen = 0]) =>
    v is List && v.length >= minLen && v.length <= maxLen && v.every((x) => _isInt(x, 0, 1188));
bool _previous(Object? v) {
  try {
    parsePrevious(v);
    return true;
  } catch (_) {
    return false;
  }
}

final _chapterKey = RegExp(r'^(0|[1-9]\d{0,3})$');
bool _chapterRecord(Object? v, bool Function(Object?) value) =>
    v is Map &&
    v.entries.every((e) => e.key is String && _chapterKey.hasMatch(e.key as String) && int.parse(e.key as String) < 1189 && value(e.value));

void _validateStateShape(Object? raw) {
  final s = _obj(raw, [
    'id', 'chapterSchema', 'chapterCorrection', 'editionReview', 'sessions', 'config', 'lang', 'pendingBookOrder',
    'previouslyRead', 'completionDays', 'done', 'logs', 'timer', 'ops', 'pace', 'adaptive',
  ]);
  _check(s['id'] is String && uuidPattern.hasMatch(s['id'] as String));
  _check(!s.containsKey('chapterSchema') || s['chapterSchema'] == 2);
  if (s.containsKey('chapterCorrection')) {
    final c = _obj(s['chapterCorrection'], ['previouslyRead', 'done', 'samples']);
    final ref = RegExp(r'^(JOL [1-3]|MAL [1-4])$');
    _check(c['previouslyRead'] is List &&
        (c['previouslyRead'] as List).length <= 7 &&
        (c['previouslyRead'] as List).every((r) => r is String && ref.hasMatch(r)));
    _check(c['done'] is Map &&
        (c['done'] as Map).entries.every((e) => e.key is String && ref.hasMatch(e.key as String) && _isDate(e.value)));
    _check(c['samples'] is List && (c['samples'] as List).length <= 1189);
    for (final x in c['samples'] as List) {
      final sample = _obj(x, ['day', 'references', 'seconds']);
      _check(_isInt(sample['day'], 0, 3649) && _isInt(sample['seconds'], 1, 9007199254740991));
      final refs = sample['references'];
      _check(refs is List &&
          refs.length <= 1189 &&
          refs.every((r) => r is String && RegExp(r'^[1-3A-Z]{3} [1-9]\d{0,2}$').hasMatch(r)));
    }
  }
  if (s.containsKey('editionReview')) {
    final r = s['editionReview'];
    _check(r is List && r.length <= 10000 && r.every((x) => x is String && x.length <= 200));
  }
  if (s.containsKey('sessions')) {
    final list = s['sessions'];
    _check(list is List && list.length <= 100000);
    for (final x in list as List) {
      final session = _obj(x, ['id', 'day', 'date', 'chapters', 'seconds']);
      _check(session['id'] is String && (session['id'] as String).length <= 100);
      _check(_isInt(session['day'], 0, 3649) && _isDate(session['date']) && _previous(session['chapters']));
      _check(_isInt(session['seconds'], 0, 315576000));
    }
  }
  try {
    parseConfig(s['config']);
  } catch (_) {
    throw _bad;
  }
  _check(isLanguage(s['lang']));
  _check(!s.containsKey('pendingBookOrder') || bookOrders.contains(s['pendingBookOrder']));
  _check(!s.containsKey('previouslyRead') || _previous(s['previouslyRead']));
  _check(!s.containsKey('completionDays') || _chapterRecord(s['completionDays'], (v) => _isInt(v, 0, 3649)));
  _check(_chapterRecord(s['done'], _isDate));
  final logs = s['logs'];
  _check(logs is List && logs.length <= 100000);
  for (final x in logs as List) {
    final log = _obj(x, ['day', 'seconds', 'at', 'readingDate']);
    _check(_isInt(log['day'], 0, 3649) && _isInt(log['seconds'], 0, 315576000) && _isTimestamp(log['at']));
    _check(!log.containsKey('readingDate') || _isDate(log['readingDate']));
  }
  _check(s.containsKey('timer') && s['timer'] == null);
  final ops = s['ops'];
  _check(ops is List && ops.length <= 20 && ops.every((o) => o is String && uuidPattern.hasMatch(o)));
  if (s.containsKey('pace')) {
    final p = _obj(s['pace'], ['samples', 'draft']);
    _check(p['samples'] is List && (p['samples'] as List).length <= 1189);
    for (final x in p['samples'] as List) {
      final sample = _obj(x, ['day', 'review', 'chapters', 'seconds']);
      _check(_isInt(sample['day'], 0, 3649) && _intList(sample['chapters'], 1189, 1));
      _check(_isInt(sample['seconds'], 1, 9007199254740991));
      _check(!sample.containsKey('review') || ['confirmed', 'excluded'].contains(sample['review']));
    }
    _check(p.containsKey('draft'));
    if (p['draft'] != null) {
      final d = _obj(p['draft'], ['day', 'before', 'secondsBefore', 'manual']);
      _check(_isInt(d['day'], 0, 3649) && _intList(d['before'], 1189));
      _check(_isInt(d['secondsBefore'], 0, 9007199254740991));
      _check(!d.containsKey('manual') || d['manual'] is bool);
    }
  }
  if (s.containsKey('adaptive')) {
    final a = _obj(s['adaptive'], ['date', 'unplanned', 'days', 'finished', 'extra']);
    _check(_isDate(a['date']));
    _check(!a.containsKey('unplanned') || _previous(a['unplanned']));
    _check(a['days'] is List && (a['days'] as List).length <= 3650 && (a['days'] as List).every((d) => _intList(d, 1189)));
    _check(a['finished'] is List &&
        (a['finished'] as List).length <= 3650 &&
        (a['finished'] as List).every((d) => _isInt(d, 0, 3649)));
    _check(a['extra'] is Map &&
        (a['extra'] as Map).entries.every((e) =>
            e.key is String && _chapterKey.hasMatch(e.key as String) && _intList(e.value, 1189)));
  }
}

Backup parseBackup(String raw) {
  if (raw.length > maxBackupBytes) throw _bad;
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    throw _bad;
  }
  final top = _obj(json, ['app', 'version', 'exportedAt', 'theme', 'state']);
  _check(top['app'] == 'leseweg' && _isInt(top['version'], 1, 8) && _isTimestamp(top['exportedAt']));
  _check(top['theme'] == 'light' || top['theme'] == 'dark');
  _validateStateShape(top['state']);
  final version = (top['version'] as num).toInt();
  var state = ReadingState.fromJson((top['state'] as Map).cast());
  if (version >= 6 && state.chapterSchema != 2) throw _bad;
  final int days;
  try {
    days = duration(state.config);
  } catch (_) {
    throw _bad;
  }
  final expected = {for (final c in scopeFor(state.config)) c.id};
  final previous = (state.previouslyRead ?? []).toSet();
  _check(!previous.any((id) => !expected.contains(id) || state.done.containsKey(id)));
  _check(!state.done.keys.any((id) => !expected.contains(id)));
  _check(!state.logs.any((l) => l.day >= days));
  _check(!(state.completionDays ?? {}).entries.any((e) => !state.done.containsKey(e.key) || e.value >= days));
  final sessions = state.sessions;
  if (sessions != null) {
    _check(sessions.map((s) => s.id).toSet().length == sessions.length);
    _check(!sessions.any((s) => s.day >= days || s.chapters.any((id) => !expected.contains(id))));
  }
  final pace = state.pace;
  if (pace != null) {
    final ids = [for (final s in pace.samples) ...s.chapters];
    _check(ids.toSet().length == ids.length &&
        !ids.any((id) => !state.done.containsKey(id)) &&
        !pace.samples.any((s) => s.day >= days) &&
        !(pace.draft != null &&
            (pace.draft!.day >= days || pace.draft!.before.toSet().length != pace.draft!.before.length)));
  }
  final adaptive = state.adaptive;
  if (isBible52(state.config)) {
    final s = state;
    bool sameList(List<int>? a, List<int> b) =>
        a != null && a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);
    _check(!(version < 8 ||
        s.chapterSchema != 2 ||
        s.sessions == null ||
        s.pace == null ||
        s.completionDays == null ||
        s.pendingBookOrder != null ||
        adaptive == null ||
        (adaptive.unplanned?.isNotEmpty ?? false) ||
        adaptive.extra.isNotEmpty ||
        bible52Units.any((u) => !sameList(u.index < adaptive.days.length ? adaptive.days[u.index] : null,
            [for (final c in u.chapters) if (!previous.contains(c.id)) c.id])) ||
        s.done.keys.any((id) => s.completionDays![id] != bible52ChapterUnit[id]) ||
        adaptive.finished.any((day) =>
            day >= bible52Units.length ||
            !bible52Units[day].chapters.every((c) => previous.contains(c.id) || s.done.containsKey(c.id))) ||
        [...s.sessions!.map((x) => (x.day, x.chapters)), ...s.pace!.samples.map((x) => (x.day, x.chapters))]
            .any((x) => x.$2.any((id) => bible52ChapterUnit[id] != x.$1))));
  }
  if (adaptive != null) {
    final ids = [for (final d in adaptive.days) ...d];
    final pending = adaptive.unplanned ?? [];
    final scheduled = [...ids, ...pending];
    final extras = [for (final e in adaptive.extra.values) ...e];
    _check(!scheduled.any((id) => !expected.contains(id) || previous.contains(id)) &&
        scheduled.toSet().length == scheduled.length &&
        !pending.any((id) => state.done.containsKey(id)) &&
        !extras.any((id) => !expected.contains(id) || previous.contains(id)));
    // Version 4 records overdue chapters explicitly. Legacy files can lack that
    // list; their remaining chapters are recovered by redistribution as before.
    if (version >= 4) {
      final accounted = {...previous, ...state.done.keys, ...scheduled, ...extras};
      _check(accounted.length == expected.length);
      // A reopened unit can contain a newly unchecked chapter only in extra.
      // Recommendations stay stable until completion, so compare the scheduled
      // subsequence, not that temporarily detached chapter's absolute position.
      final scheduledIds = scheduled.toSet();
      final unread = [
        for (final c in orderedChapters(state.config))
          if (scheduledIds.contains(c.id) && !state.done.containsKey(c.id)) c.id,
      ];
      final assigned = scheduled.where((id) => !state.done.containsKey(id)).toList();
      if (state.chapterSchema == 2) {
        for (final (index, id) in unread.indexed) {
          _check(index < assigned.length && assigned[index] == id);
        }
      }
    }
    _check(adaptive.days.length == days &&
        ids.length == ids.toSet().length &&
        !adaptive.finished.any((d) => d >= days) &&
        !adaptive.extra.entries.any((e) => e.key >= days || e.value.toSet().length != e.value.length));
  }
  if (state.chapterSchema != 2) {
    state = prepareState(state, state.adaptive?.date ?? state.config.start)..timer = null;
  }
  return Backup(version, top['exportedAt'] as String, top['theme'] as String, state);
}

String makeBackup(ReadingState state, Lang lang, String theme, [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final snapshot =
      (state.chapterSchema == 2 ? state : prepareState(state, state.adaptive?.date ?? state.config.start)).copy();
  // A backup records elapsed time at export, never a timer that keeps running
  // for days until the file is restored on another device.
  final timer = snapshot.timer;
  if (timer != null) {
    final seconds = max(0, ((now - timer.startedAt) / 1000).floor());
    if (seconds > 0) {
      snapshot.logs.add(TimeLog(
        day: timer.day,
        readingDate: today(snapshot.config.timezone, timer.startedAt),
        seconds: seconds,
        at: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String(),
      ));
    }
  }
  final adaptive = snapshot.adaptive;
  if (adaptive != null) {
    final accounted = {
      ...?snapshot.previouslyRead,
      ...snapshot.done.keys,
      for (final d in adaptive.days) ...d,
      for (final e in adaptive.extra.values) ...e,
    };
    adaptive.unplanned = [for (final c in orderedChapters(snapshot.config)) if (!accounted.contains(c.id)) c.id];
  }
  snapshot.timer = null;
  snapshot.ops = [];
  snapshot.lang = lang;
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'leseweg',
    'version': 8,
    'exportedAt': DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String(),
    'theme': theme == 'dark' ? 'dark' : 'light',
    'state': snapshot.toJson(),
  });
}
