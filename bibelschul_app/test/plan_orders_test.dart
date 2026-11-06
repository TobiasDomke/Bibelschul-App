// "Chronologisch mit Psalmen", "AT & NT parallel" and the adaptive goal of
// the 52-week plan.
import 'dart:collection';

import 'package:bibelschul_app/app/plan_view.dart';
import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/adaptive.dart';
import 'package:bibelschul_app/core/editions.dart';
import 'package:bibelschul_app/core/plan_code.dart';
import 'package:bibelschul_app/core/planner.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/core/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Config config(String order, {String scope = 'bible', String edition = 'schlachter2000'}) => parseConfig({
      'amount': 12, 'unit': 'months', 'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin',
      'scope': scope, 'order': order, 'keepTogether': true, 'edition': edition,
    });

Chapter ch(String code, int number) => chapters.firstWhere((c) => c.code == code && c.number == number);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('new orders cover every chapter exactly once in every edition and scope', () {
    for (final edition in editionIds) {
      for (final scope in ['bible', 'ot', 'nt']) {
        for (final order in ['chronoPsalms', 'parallel']) {
          final c = config(order, scope: scope, edition: edition);
          final plan = createPlan(c);
          final ids = [for (final d in plan) for (final ch in d.chapters) ch.id];
          expect(ids.toSet().length, scopeFor(c).length, reason: '$edition $scope $order');
          expect(ids.length, scopeFor(c).length, reason: '$edition $scope $order');
        }
      }
    }
  });

  test('psalms follow the event they belong to; the rest accompany the year', () {
    final order = orderedChapters(config('chronoPsalms'));
    int at(String code, int n) => order.indexWhere((c) => c.code == code && c.number == n);
    expect(at('PSA', 51), at('2SA', 12) + 1);
    expect([at('PSA', 56), at('PSA', 34)], [at('1SA', 21) + 1, at('1SA', 21) + 2]);
    expect(at('PSA', 22), at('MAT', 27) + 1);
    expect(at('PSA', 119), at('NEH', 8) + 1);

    final c = config('chronoPsalms');
    final companions = companionPsalms(c);
    expect(companions.length, greaterThan(60));
    expect(companions.every((id) => chapters[id].code == 'PSA'), isTrue);
    expect(psalmAnchor(c, ch('PSA', 51).id)?.code, '2SA');
    expect(psalmAnchor(c, ch('PSA', 1).id), isNull);

    // Companion psalms are spread over the whole plan, not bunched up.
    final positions = [for (final (i, x) in order.indexed) if (companions.contains(x.id)) i];
    expect(positions.first, lessThan(40));
    expect(positions.last, greaterThan(order.length - 40));
    final plan = createPlan(c);
    final daysWithPsalm = plan.where((d) => d.chapters.any((x) => x.code == 'PSA')).length;
    expect(daysWithPsalm, greaterThan(100));

    // In an Old Testament plan the psalms quoted in the New Testament are companions.
    expect(companionPsalms(config('chronoPsalms', scope: 'ot')).contains(ch('PSA', 22).id), isTrue);
  });

  test('AT & NT parallel: both testaments every day, finishing together', () {
    final plan = createPlan(config('parallel'));
    expect(plan.first.chapters.map((c) => c.code).toSet(), containsAll(['GEN', 'MAT']));
    final lastOt = plan.lastIndexWhere((d) => d.chapters.any((c) => c.bookIndex < 39));
    final lastNt = plan.lastIndexWhere((d) => d.chapters.any((c) => c.bookIndex >= 39));
    expect((lastOt - lastNt).abs(), lessThan(4));
    final withNt = plan.where((d) => d.chapters.any((c) => c.bookIndex >= 39)).length;
    expect(withNt, greaterThan(plan.length * 0.6));
  });

  test('days stay about equally long in the new orders', () {
    for (final order in ['chronoPsalms', 'parallel']) {
      final minutes = [for (final d in createPlan(config(order))) d.words / 130]..sort();
      expect(minutes[minutes.length ~/ 10], greaterThan(12), reason: order);
      expect(minutes[minutes.length * 9 ~/ 10], lessThan(20), reason: order);
    }
  });

  test('day display: New Testament first, companion psalm last', () {
    final parallel = config('parallel');
    expect(displayOrder([ch('GEN', 1), ch('GEN', 2), ch('MAT', 1)], parallel).first.code, 'MAT');
    final psalms = config('chronoPsalms');
    final companion = chapters[companionPsalms(psalms).first];
    expect(displayOrder([companion, ch('GEN', 1)], psalms).last, companion);
  });

  test('new orders survive validation and plan codes', () {
    for (final order in ['chronoPsalms', 'parallel']) {
      final code = encodePlanCode(config(order), 'Klasse');
      expect(decodePlanCode(code, time: '07:00', timezone: 'Europe/Berlin')?.config.order, order);
    }
  });

  group('52-week plan goal', () {
    ReadingState state(Map<String, String> done) {
      final s = ReadingState.fromJson({
        'version': 9, 'id': 'x', 'lang': 'de', 'updatedAt': '2026-11-05T00:00:00Z',
        'config': {
          'template': 'bible52', 'edition': 'schlachter2000', 'amount': 52, 'unit': 'weeks', 'scope': 'bible',
          'order': 'canonical', 'keepTogether': false, 'bookOrder': 'western', 'bookOrderMode': 'manual',
          'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin',
        },
        'done': done,
        'logs': [],
        'ops': [],
        'completionDays': {},
      });
      final finished = <int>[
        for (final u in bible52Units)
          if (u.chapters.every((c) => done.containsKey('${c.id}'))) u.index,
      ];
      s.adaptive = Adaptive(date: '1970-01-01', days: [], extra: SplayTreeMap(), finished: finished, unplanned: []);
      return s;
    }

    Map<String, String> read(int units, String date) => {
          for (final u in bible52Units.take(units))
            for (final c in u.chapters) '${c.id}': date,
        };

    test('on schedule it is exactly one section a day', () {
      final goal = bible52Goal(state(read(10, '2026-11-10')), '2026-11-11')!;
      expect(goal.target, 1);
      expect(goal.doneToday, 0);
      expect(goal.end, addDays('2026-11-01', 363));
    });

    test('skipped days are spread: some days get two sections, never all at once', () {
      final s = state(read(10, '2026-11-10'));
      // Ten days without reading: 20 units behind on day 30.
      final targets = <int>[];
      var units = 10;
      for (var day = 20; day < 120; day++) {
        final date = addDays('2026-11-01', day);
        final goal = bible52Goal(state(read(units, '2026-11-10')), date)!;
        targets.add(goal.target);
        units += goal.target;
      }
      expect(targets.every((t) => t <= 2), isTrue);
      expect(targets.where((t) => t == 2).length, greaterThan(3));
      expect(bible52Goal(s, '2026-10-01'), isNull);
    });

    test('sections read today count towards the goal', () {
      final goal = bible52Goal(state(read(11, '2026-11-11')), '2026-11-11')!;
      expect(goal.doneToday, 11);
      expect(goal.target, greaterThanOrEqualTo(1));
    });
  });
}
