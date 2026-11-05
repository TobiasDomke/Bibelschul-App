// Port of lib/actions.ts. Every change to a reading plan goes through applyAction.
import 'dart:collection';
import 'dart:math';

import 'adaptive.dart';
import 'book_order.dart';
import 'deadline.dart';
import 'edition_migration.dart';
import 'editions.dart';
import 'languages.dart';
import 'pace.dart';
import 'planner.dart';
import 'session_stats.dart';
import 'state.dart';
import 'util.dart';

const _invalid = AppError('invalid-op');

T _req<T>(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! T) throw _invalid;
  return v;
}

int _int(Map<String, Object?> m, String key, int min, int max) {
  final v = m[key];
  if (v is! num || v != v.roundToDouble() || v < min || v > max) throw _invalid;
  return v.toInt();
}

void _keys(Map<String, Object?> m, List<String> allowed) {
  if (m.keys.any((k) => !allowed.contains(k))) throw _invalid;
}

bool _isTime(Object? v) => v is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v);
bool _isZone(Object? v) => v is String && v.length <= 100 && isValidTimezone(v);

/// Validates a stored/imported Config map strictly (zod `configSchema`).
Config parseConfig(Object? raw) {
  if (raw is! Map) throw _invalid;
  final m = raw.cast<String, Object?>();
  _keys(m, ['template', 'edition', 'scope', 'order', 'keepTogether', 'bookOrder', 'bookOrderMode', 'amount', 'unit',
      'start', 'time', 'timezone']);
  bool optEnum(String key, List<String> values) => m[key] == null && !m.containsKey(key) || values.contains(m[key]);
  if (!optEnum('template', ['bible52']) ||
      !optEnum('edition', editionIds) ||
      !optEnum('scope', ['bible', 'ot', 'nt']) ||
      !optEnum('order', ['canonical', 'chronological', 'mixed']) ||
      !(m.containsKey('keepTogether') ? m['keepTogether'] is bool : true) ||
      !optEnum('bookOrder', bookOrders) ||
      !optEnum('bookOrderMode', ['auto', 'manual'])) {
    throw _invalid;
  }
  _int(m, 'amount', 1, 3650);
  if (!['days', 'weeks', 'months'].contains(m['unit']) || m['start'] is! String) throw _invalid;
  if (!_isTime(m['time']) || !_isZone(m['timezone'])) throw _invalid;
  return Config.fromJson(m);
}

/// zod `previousSchema`: unique chapter ids 0..1188.
List<int> parsePrevious(Object? raw) {
  if (raw is! List || raw.length > 1189) throw _invalid;
  final ids = <int>[];
  for (final v in raw) {
    if (v is! num || v != v.roundToDouble() || v < 0 || v > 1188) throw _invalid;
    ids.add(v.toInt());
  }
  if (ids.toSet().length != ids.length) throw _invalid;
  return ids;
}

Map<String, Object?> _parseOp(Object? raw) {
  if (raw is! Map) throw _invalid;
  final m = raw.cast<String, Object?>();
  final action = m['action'];
  bool uuidOk(Object? v) => v is String && uuidPattern.hasMatch(v);
  if (!uuidOk(m['opId'])) throw _invalid;
  if (action != 'create' && m['planId'] is! String) throw _invalid;
  final base = ['action', 'planId', 'opId'];
  switch (action) {
    case 'review-pace':
      _keys(m, [...base, 'index', 'seconds', 'review']);
      _int(m, 'index', 0, 1188);
      if (_req<num>(m, 'seconds') <= 0 || m['seconds'] != (m['seconds'] as num).roundToDouble()) throw _invalid;
      if (!['auto', 'confirmed', 'excluded'].contains(m['review'])) throw _invalid;
    case 'edition':
      _keys(m, [...base, 'edition']);
      if (!editionIds.contains(m['edition'])) throw _invalid;
    case 'review-edition':
      _keys(m, base);
    case 'language':
      _keys(m, [...base, 'lang']);
      if (!isLanguage(m['lang'])) throw _invalid;
    case 'book-order':
      _keys(m, [...base, 'choice', 'lang']);
      if (!['auto', ...bookOrders].contains(m['choice']) || !isLanguage(m['lang'])) throw _invalid;
    case 'previous':
      _keys(m, [...base, 'previouslyRead']);
      m['previouslyRead'] = parsePrevious(m['previouslyRead']);
    case 'deadline':
      _keys(m, [...base, 'end']);
      if (m['end'] is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(m['end'] as String)) throw _invalid;
    case 'extend' || 'reopen':
      _keys(m, [...base, 'day']);
      _int(m, 'day', 0, 3649);
    case 'create':
      _keys(m, [...base, 'config', 'previouslyRead', 'lang']);
      if (m['planId'] != null && m['planId'] is! String) throw _invalid;
      m['config'] = parseConfig(m['config']);
      if (m['previouslyRead'] != null) m['previouslyRead'] = parsePrevious(m['previouslyRead']);
      if (!isLanguage(m['lang'])) throw _invalid;
    case 'chapter':
      _keys(m, [...base, 'chapter', 'done']);
      _int(m, 'chapter', 0, 1188);
      _req<bool>(m, 'done');
    case 'complete':
      _keys(m, [...base, 'paceChoice', 'day']);
      if (m['paceChoice'] != null && !['confirmed', 'excluded'].contains(m['paceChoice'])) throw _invalid;
      _int(m, 'day', 0, 3649);
    case 'timer':
      _keys(m, [...base, 'mode', 'day']);
      if (!['start', 'pause', 'stop'].contains(m['mode'])) throw _invalid;
      _int(m, 'day', 0, 3649);
    case 'correct':
      _keys(m, [...base, 'day', 'minutes']);
      _int(m, 'day', 0, 3649);
      final minutes = _req<num>(m, 'minutes');
      if (minutes < 0 || minutes > 1440) throw _invalid;
    case 'settings':
      _keys(m, [...base, 'time', 'timezone', 'lang']);
      if (!_isTime(m['time']) || !_isZone(m['timezone']) || !isLanguage(m['lang'])) throw _invalid;
    default:
      throw _invalid;
  }
  return m;
}

ReadingState applyAction(ReadingState? current, Map<String, Object?> raw, [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final op = _parseOp(Map.of(raw));
  final action = op['action'] as String;
  final opId = op['opId'] as String;
  var state = current?.copy();
  if (state != null) state = prepareState(state, today(state.config.timezone, now));
  if (state != null && state.ops.contains(opId)) return state;
  if (state != null) state.pace = paceState(state);
  int opDay() => (op['day'] as num).toInt();
  final hasDay = op.containsKey('day');

  if (action == 'create') {
    if ((state?.id) != op['planId']) throw const AppError('stale');
    var config = op['config'] as Config;
    final lang = parseLang(op['lang'])!;
    if (isBible52(config)) config = bible52Config(config);
    config.edition ??= languageEdition(lang);
    // Each new plan pins a concrete edition; older stored plans retain their basis.
    if (config.bookOrderMode == 'auto') {
      config.bookOrder = config.edition != null ? editions[config.edition]!.order : languageBookOrder(lang);
    }
    final previous = op['previouslyRead'] as List<int>?;
    try {
      createPlan(config, previous ?? []);
    } catch (_) {
      throw const AppError('invalid');
    }
    state = ReadingState(
      id: uuid(),
      chapterSchema: 2,
      config: config,
      lang: lang,
      completionDays: isBible52(config) ? SplayTreeMap() : null,
      previouslyRead: previous ?? [],
      sessions: [],
      pace: PaceState(),
    );
  } else {
    if (state == null || state.id != op['planId']) throw const AppError('stale');
    final s = state;
    final fixed = isBible52(s.config);
    if (fixed && ['edition', 'book-order', 'deadline', 'extend'].contains(action)) throw const AppError('invalid');
    final openUnit = s.timer?.day ?? s.pace?.draft?.day;
    final requestedUnit = action == 'chapter'
        ? bible52ChapterUnit[(op['chapter'] as num).toInt()]
        : hasDay
            ? opDay()
            : null;
    if (fixed &&
        openUnit != null &&
        (action == 'previous' ||
            (['chapter', 'timer', 'complete', 'reopen', 'correct'].contains(action) && requestedUnit != openUnit))) {
      throw const AppError('timer');
    }
    s.sessions = sessionsFor(s);
    final days = createPlan(s.config, s.previouslyRead ?? []);
    if (hasDay && opDay() >= days.length) throw const AppError('invalid');
    final date = today(s.config.timezone, now);
    final currentDay = dayIndex(s.config, date);
    if (action == 'timer' && s.timer != null && s.timer!.day != opDay()) throw const AppError('timer');
    if (!fixed && hasDay && action != 'correct' && opDay() != currentDay && s.timer?.day != opDay()) {
      throw const AppError('day');
    }
    void stop() {
      final timer = s.timer;
      if (timer == null) return;
      final seconds = max(0, ((now - timer.startedAt) / 1000).floor());
      if (seconds > 0) {
        s.logs.add(TimeLog(
          day: timer.day,
          readingDate: today(s.config.timezone, timer.startedAt),
          seconds: seconds,
          at: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String(),
        ));
      }
      s.timer = null;
    }

    switch (action) {
      case 'review-pace':
        final index = (op['index'] as num).toInt();
        final samples = s.pace!.samples;
        if (index >= samples.length || samples[index].seconds != (op['seconds'] as num).toInt()) {
          throw const AppError('stale');
        }
        samples[index].review = op['review'] == 'auto' ? null : op['review'] as String;
      case 'edition':
        if (s.timer != null) throw const AppError('timer');
        changeEdition(s, op['edition'] as String);
        state = prepareState(s, date);
      case 'review-edition':
        s.editionReview = null;
      case 'previous':
        if (s.timer != null) throw const AppError('timer');
        final previouslyRead = op['previouslyRead'] as List<int>;
        final allowed = {for (final c in scopeFor(s.config)) c.id};
        if (previouslyRead.any((id) => !allowed.contains(id) || s.done.containsKey(id))) {
          throw const AppError('invalid');
        }
        s.previouslyRead = previouslyRead;
        if (fixed) {
          // Confirming prior progress also closes mixed units containing chapters
          // already measured in the app; they need no empty completion session.
          final previous = previouslyRead.toSet();
          s.adaptive!.finished = [
            for (final u in bible52Units)
              if (u.chapters.every((c) => previous.contains(c.id) || s.done.containsKey(c.id))) u.index,
          ];
        }
        redistribute(s, currentDay + (s.adaptive!.finished.contains(currentDay) ? 1 : 0), date);
      case 'deadline':
        state = rescheduleDeadline(s, op['end'] as String, date);
      case 'chapter':
        final chapter = (op['chapter'] as num).toInt();
        if ((s.previouslyRead?.contains(chapter) ?? false) || !scopeFor(s.config).any((c) => c.id == chapter)) {
          throw const AppError('invalid');
        }
        if (!fixed && s.adaptive!.finished.contains(currentDay)) throw const AppError('finished');
        if (op['done'] == true) {
          s.done[chapter] = date;
          s.completionDays?[chapter] = fixed ? bible52ChapterUnit[chapter]! : currentDay;
        } else {
          s.completionDays?.remove(chapter);
          s.done.remove(chapter);
          forgetPaceChapter(s, chapter);
        }
      case 'complete':
        final day = opDay();
        if (s.timer != null && s.timer!.day != day) throw const AppError('timer');
        if (s.timer?.day == day) stop();
        final recorded = {for (final x in s.sessions!) ...x.chapters};
        final ids = s.done.keys
            .where((id) => !recorded.contains(id) && (!fixed || bible52ChapterUnit[id] == day))
            .toList();
        final seconds = max(
            0,
            s.logs.where((l) => l.day == day).fold<int>(0, (n, l) => n + l.seconds) -
                s.sessions!.where((x) => x.day == day).fold<int>(0, (n, x) => n + x.seconds));
        if (!s.adaptive!.finished.contains(fixed ? day : currentDay) && (ids.isNotEmpty || seconds > 0)) {
          final dayLogs = s.logs.where((l) => l.day == day).toList();
          s.sessions!.add(Session(
            id: opId,
            day: day,
            date: (dayLogs.isEmpty ? null : dayLogs.last.readingDate) ?? date,
            chapters: ids,
            seconds: seconds,
          ));
        }
        finishPace(s, day, op['paceChoice'] as String?);
        if (!fixed ||
            bible52Units[day]
                .chapters
                .every((c) => s.done.containsKey(c.id) || (s.previouslyRead?.contains(c.id) ?? false))) {
          s.adaptive!.finished = {...s.adaptive!.finished, fixed ? day : currentDay}.toList();
        }
        redistribute(s, currentDay + 1, date);
      case 'extend':
        final day = opDay();
        if (s.adaptive!.finished.contains(day)) throw const AppError('finished');
        final extra = nextExtraChapter(s, day);
        if (extra != null) s.adaptive!.extra[day] = [...?s.adaptive!.extra[day], extra.id];
      case 'reopen':
        final day = opDay();
        s.adaptive!.finished = s.adaptive!.finished.where((d) => d != day).toList();
        redistribute(s, currentDay, date);
      case 'timer':
        final day = opDay();
        if (s.timer != null && s.timer!.day != day) throw const AppError('timer');
        if (op['mode'] == 'start' && s.timer == null) {
          if (s.adaptive!.finished.contains(day)) throw const AppError('finished');
          startPace(s, day);
          s.timer = TimerState(day, now);
        }
        if (op['mode'] != 'start') stop();
      case 'correct':
        _correct(s, opDay(), (op['minutes'] as num).toDouble(), now, date, fixed, stop);
      case 'settings':
        s.config.time = op['time'] as String;
        s.config.timezone = op['timezone'] as String;
    }
    final lang = parseLang(op['lang']);
    if (fixed && (action == 'language' || action == 'settings')) state.lang = lang!;
    if (!fixed && (action == 'language' || (action == 'settings' && state.lang != lang) || action == 'book-order')) {
      final st = state;
      st.lang = lang!;
      if (action == 'book-order') st.config.bookOrderMode = op['choice'] == 'auto' ? 'auto' : 'manual';
      // Selecting a language opts legacy plans into automatic book order.
      st.config.bookOrderMode ??= 'auto';
      final String wanted = action == 'book-order' && op['choice'] != 'auto'
          ? op['choice'] as String
          : st.config.bookOrderMode == 'auto'
              ? (st.config.edition != null ? editions[st.config.edition]!.order : languageBookOrder(lang))
              : (st.pendingBookOrder ?? st.config.bookOrder ?? 'western');
      if (wanted != (st.config.bookOrder ?? 'western')) {
        st.pendingBookOrder = wanted;
      } else {
        st.pendingBookOrder = null;
        st.config.bookOrder = wanted;
      }
    }
  }
  final result = prepareState(state, today(state.config.timezone, now));
  final ops = result.ops;
  result.ops = [...ops.sublist(max(0, ops.length - 19)), opId];
  return result;
}

void _correct(ReadingState s, int day, double minutes, int now, String date, bool fixed, void Function() stop) {
  final active = s.timer?.day == day ? s.timer : null;
  if (active != null) stop();
  final oldLogs = s.logs.where((l) => l.day == day).toList();
  final oldTotal = oldLogs.fold<int>(0, (n, l) => n + l.seconds);
  final open = s.pace?.draft?.day == day && !s.adaptive!.finished.contains(day);
  final sessions = s.sessions!.where((x) => x.day == day).toList();
  final total = jsRound(minutes * 60);
  var assigned = 0;
  for (final (i, x) in sessions.indexed) {
    final value = i == sessions.length - 1 && !open
        ? total - assigned
        : jsRound(total * (oldTotal > 0 ? x.seconds / oldTotal : 1 / (sessions.length + (open ? 1 : 0))));
    x.seconds = max(0, min(total - assigned, value));
    assigned += x.seconds;
  }
  final dates = <String, int>{};
  for (final log in oldLogs) {
    final d = logDate(s, log);
    dates[d] = (dates[d] ?? 0) + log.seconds;
  }
  if (dates.isEmpty) {
    dates[active != null
        ? today(s.config.timezone, active.startedAt)
        : fixed
            ? date
            : addDays(s.config.start, day)] = 0;
  }
  s.logs = s.logs.where((l) => l.day != day).toList();
  var allocated = 0;
  for (final (i, entry) in dates.entries.indexed) {
    final value = i == dates.length - 1
        ? total - allocated
        : jsRound(total * (oldTotal > 0 ? entry.value / oldTotal : 1 / dates.length));
    final part = max(0, min(total - allocated, value));
    allocated += part;
    if (part > 0) {
      s.logs.add(TimeLog(
          day: day,
          readingDate: entry.key,
          seconds: part,
          at: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String()));
    }
  }
  correctPace(s, day);
}
