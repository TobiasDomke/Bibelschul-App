// Port of lib/exports.ts (calendar and CSV files).
import 'dart:convert';

import '../i18n/i18n.dart';
import 'adaptive.dart';
import 'languages.dart';
import 'pace.dart';
import 'planner.dart';
import 'reading_time.dart';
import 'state.dart';
import 'util.dart';

String _escapeICS(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll(',', '\\,').replaceAll(';', '\\;');

String _fold(String s) {
  var current = '', result = '';
  for (final c in s.runes.map(String.fromCharCode)) {
    if (utf8.encode(current + c).length > 73) {
      result += '$current\r\n';
      current = ' ';
    }
    current += c;
  }
  return result + current;
}

String _stamp(DateTime d) =>
    d.toUtc().toIso8601String().replaceAll(RegExp('[-:]'), '').replaceAll(RegExp(r'\.\d{3}'), '');

/// [origin] is an optional link target (the web app); the native app omits it.
String calendarFile(ReadingState state, Lang lang, [String? origin, DateTime? stampAt]) {
  final pace = readingPace(state);
  int estimate(int words) => estimatedMinutes(words, pace);
  final t = text(lang), names = bookNames(isBible52(state.config) ? Lang.de : lang);
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Leseweg//Bible Plan//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escapeICS('Leseweg')}',
  ];
  for (final day in readingPlan(state, state.adaptive?.date ?? state.config.start)) {
    if (day.chapters.isEmpty) continue;
    final start = zonedUTC(day.date, state.config.time, state.config.timezone);
    final title = '${t.calendarTitle}: ${passage(day.chapters, names)}';
    final link = origin == null ? '' : '\n$origin/?day=${day.index}';
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${state.id}-${day.index}@leseweg',
      'DTSTAMP:${_stamp(stampAt ?? DateTime.now())}',
      'DTSTART:${_stamp(start)}',
      'DTEND:${_stamp(start.add(Duration(minutes: estimate(day.words))))}',
      'SUMMARY:${_escapeICS(title)}',
      'DESCRIPTION:${_escapeICS('${t.day} ${day.index + 1}\n${passage(day.chapters, names)}\n${t.approx} ${readingTime(estimatedSeconds(day.words, pace), lang)}$link')}',
      if (origin != null) 'URL:$origin/?day=${day.index}',
      'BEGIN:VALARM',
      'TRIGGER:PT0S',
      'ACTION:DISPLAY',
      'DESCRIPTION:${_escapeICS(title)}',
      'END:VALARM',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String csvFile(ReadingState state, Lang lang, [int? now]) {
  final pace = readingPace(state);
  final t = text(lang), names = bookNames(isBible52(state.config) ? Lang.de : lang);
  final previous = scopeFor(state.config).where((c) => state.previouslyRead?.contains(c.id) ?? false).toList();
  String minutesValue(num seconds) {
    final v = jsRound(seconds / 6) / 10;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  final rows = <List<Object>>[
    [t.day, t.startDate, t.chapters, t.estimate, t.measured, t.read],
    if (previous.isNotEmpty)
      [
        planText(lang).previous,
        '',
        passage(previous, names),
        estimatedMinutes(previous.fold<int>(0, (sum, c) => sum + c.words), pace),
        '',
        passage(previous, names),
      ],
    for (final d in readingPlan(state, state.adaptive?.date ?? state.config.start))
      [
        d.index + 1,
        d.date,
        passage(d.chapters, names),
        estimatedMinutes(d.words, pace),
        minutesValue(daySeconds(state, d.index, now)),
        passage(readChaptersOnDay(state, d.index), names),
      ],
  ];
  return '﻿${rows.map((row) => row.map((v) => '"${'$v'.replaceAll('"', '""')}"').join(';')).join('\r\n')}';
}
