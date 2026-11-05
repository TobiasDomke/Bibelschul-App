// Compares the Dart port with reference results recorded from the TypeScript
// web app. Regenerate the fixture from the repository root with
//   node scripts/flutter/export-fixtures.mjs
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/adaptive.dart';
import 'package:bibelschul_app/core/backup.dart';
import 'package:bibelschul_app/core/deadline.dart';
import 'package:bibelschul_app/core/difficulty.dart';
import 'package:bibelschul_app/core/exports.dart';
import 'package:bibelschul_app/core/languages.dart';
import 'package:bibelschul_app/core/pace.dart';
import 'package:bibelschul_app/core/planner.dart';
import 'package:bibelschul_app/core/reading_time.dart';
import 'package:bibelschul_app/core/session_stats.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/core/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Map<String, Object?> _withId(Map<String, Object?> json) => {...json, 'id': 'PLAN'};

void main() {
  tzdata.initializeTimeZones();
  // The web app balances by plain word counts at 180 words per minute. These
  // tests check the ported algorithms in exactly that mode; the app itself uses
  // the reading-effort model (core/difficulty.dart).
  legacyReadingModel = true;
  final file = File('test/fixtures/parity.json');
  if (!file.existsSync()) {
    test('parity fixture missing', () {
      fail('Run `node scripts/flutter/export-fixtures.mjs` in the repository root first.');
    });
    return;
  }
  final fx = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  test('chapter orders match the web app', () {
    final orders = (fx['orders'] as Map).cast<String, List>();
    for (final MapEntry(:key, :value) in orders.entries) {
      final [edition, scope, order, bookOrder] = key.split(':');
      final config = Config(
          edition: edition,
          scope: scope,
          order: order,
          bookOrder: bookOrder,
          amount: 1,
          unit: 'days',
          start: '2026-03-20',
          time: '07:30',
          timezone: 'Europe/Berlin');
      expect(orderedChapters(config).map((c) => c.id).toList(), value, reason: key);
    }
  });

  test('day partitions match the web app', () {
    for (final raw in fx['plans'] as List) {
      final p = raw as Map<String, Object?>;
      final config = Config.fromJson((p['config'] as Map).cast());
      final scoped = scopeFor(config);
      final prior = p['prior'] == 'sample'
          ? [for (final (i, c) in scoped.indexed) if (i % 7 == 3 || i < 15) c.id]
          : <int>[];
      final plan = createPlan(config, prior);
      expect(plan.map((d) => d.chapters.length).toList(), p['lengths'], reason: jsonEncode(p['config']));
      expect(plan.first.date, p['first']);
      expect(plan.last.date, p['last']);
    }
  });

  test('Bibelleseplan 52, month durations, time zones and time labels', () {
    final config = bible52Config(
        Config(amount: 1, unit: 'days', start: '2026-01-05', time: '07:30', timezone: 'UTC'));
    expect(createPlan(config).map((d) => d.chapters.map((c) => c.id).toList()).toList(), fx['bible52']);
    for (final raw in fx['durations'] as List) {
      final d = raw as Map;
      expect(
          duration(Config(amount: d['amount'], unit: 'months', start: d['start'], time: '07:30', timezone: 'UTC')),
          d['days'],
          reason: '$d');
    }
    for (final raw in fx['zoned'] as List) {
      final z = raw as Map;
      expect(zonedUTC(z['date'], z['time'], z['zone']).millisecondsSinceEpoch, z['ms'], reason: '$z');
    }
    for (final raw in fx['times'] as List) {
      final t = raw as Map;
      for (final lang in Lang.values) {
        expect(readingTime(t['s'] as num, lang), t[lang.name], reason: '$t');
      }
      expect(readingTimeClock(t['s'] as num), t['clock']);
    }
  });

  final scenarios = fx['scenarios'] as List;
  for (final (index, raw) in scenarios.indexed) {
    final scenario = raw as Map<String, Object?>;
    test('reading history $index matches the web app step by step', () {
      final lang = parseLang(scenario['lang'])!;
      ReadingState? state;
      for (final (stepIndex, rawStep) in (scenario['steps'] as List).indexed) {
        final step = rawStep as Map<String, Object?>;
        final now = (step['now'] as num).toInt();
        final op = (step['op'] as Map).cast<String, Object?>();
        final where = 'step $stepIndex ${jsonEncode(op)}';
        if (op['planId'] == 'PLAN') op['planId'] = state!.id;
        if (step.containsKey('error')) {
          expect(() => applyAction(state, op, now), throwsA(isA<AppError>()), reason: where);
          try {
            applyAction(state, op, now);
          } on AppError catch (e) {
            final expected = step['error'] as String;
            // zod validation errors have long messages; ours use one code.
            if (e.code != 'invalid-op') expect(e.code, expected, reason: where);
          }
          continue;
        }
        state = applyAction(state, op, now);
        final s = state;
        final ok = step['ok'] as Map<String, Object?>;
        expect(_withId(s.toJson()), ok['state'], reason: where);
        final date = today(s.config.timezone, now);
        expect(readingPlan(s, date).map((d) => d.chapters.length).toList(), ok['planLengths'], reason: where);
        final pace = readingPace(s);
        final p = ok['pace'] as Map;
        expect([pace.personal, pace.learning, pace.samples, pace.excluded, pace.chapters, pace.seconds],
            [p['personal'], p['learning'], p['samples'], p['excluded'], p['chapters'], p['seconds']],
            reason: where);
        expect(pace.secondsPerWord, closeTo(p['secondsPerWord'] as num, 1e-9), reason: where);
        final summary = readingTimeSummary(s, now, pace);
        final sm = ok['summary'] as Map;
        expect(summary.measuredSeconds, sm['measuredSeconds'], reason: where);
        expect(summary.totalSeconds, closeTo(sm['totalSeconds'] as num, 1e-6), reason: where);
        expect(summary.remainingSeconds, closeTo(sm['remainingSeconds'] as num, 1e-6), reason: where);
        expect([summary.previousChapters, summary.unmeasuredChapters, summary.remainingChapters],
            [sm['previousChapters'], sm['unmeasuredChapters'], sm['remainingChapters']],
            reason: where);
        expect(csvFile(s, lang, now), ok['csv'], reason: where);
        expect(
            calendarFile(s, lang, 'https://leseweg.pages.dev')
                .replaceAll(RegExp(r'DTSTAMP:\d+T\d+Z'), 'DTSTAMP:X')
                .replaceAll(s.id, 'PLAN'),
            ok['ics'],
            reason: where);
        final backup = jsonDecode(makeBackup(s, lang, 'dark', now)) as Map<String, Object?>;
        expect(_withId((backup['state'] as Map).cast()), ok['backup'], reason: where);
        if (ok['bounds'] != null) {
          final b = deadlineBounds(s, date);
          expect({'min': b.min, 'max': b.max}, ok['bounds'], reason: where);
        }
        expect(dailySeconds(s, now), ok['daily'], reason: where);
        final prepared = prepareState(s, date);
        final plan = readingPlan(s, date);
        final sessionDay =
            prepared.timer?.day ?? min(plan.length - 1, max(0, daysBetween(s.config.start, date)));
        expect(sessionChapters(prepared, sessionDay).map((c) => c.id).toList(), ok['session'], reason: where);
      }
    });
  }

  test('backup validation matches the web app', () {
    for (final (i, raw) in (fx['backups'] as List).indexed) {
      final b = raw as Map<String, Object?>;
      if (b['ok'] == true) {
        final parsed = parseBackup(b['raw'] as String);
        expect(_withId(parsed.state.toJson()), b['state'], reason: 'backup $i');
      } else {
        expect(() => parseBackup(b['raw'] as String), throwsA(isA<AppError>()), reason: 'backup $i');
      }
    }
  });

  test('legacy installations migrate like the web app', () {
    for (final (i, raw) in (fx['legacy'] as List).indexed) {
      final l = raw as Map<String, Object?>;
      final input = ReadingState.fromJson((l['state'] as Map).cast());
      final before = jsonEncode(input.toJson());
      final prepared = prepareState(input, l['date'] as String);
      expect(jsonEncode(input.toJson()), before, reason: 'migration never mutates the input');
      expect(_withId(prepared.toJson()), l['prepared'], reason: 'legacy $i');
      expect(_withId(prepareState(prepared, l['date'] as String).toJson()), l['prepared'], reason: 'idempotent');
      for (final (v, expected) in (l['restored'] as List).indexed) {
        final backup = jsonEncode({
          'app': 'leseweg',
          'version': v + 1,
          'exportedAt': '2026-07-01T10:00:00.000Z',
          'theme': 'light',
          'state': l['state'],
        });
        expect(_withId(parseBackup(backup).state.toJson()), expected, reason: 'legacy $i backup v${v + 1}');
      }
    }
  });
}
