// Native-only features: notes in backups, plan codes, smart reminders,
// catch-up suggestion, book progress, automatic backups and translations.
import 'dart:convert';
import 'dart:io';

import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/backup.dart';
import 'package:bibelschul_app/core/insights.dart';
import 'package:bibelschul_app/core/languages.dart';
import 'package:bibelschul_app/core/notes.dart';
import 'package:bibelschul_app/core/plan_code.dart';
import 'package:bibelschul_app/core/planner.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/core/util.dart';
import 'package:bibelschul_app/i18n/feature_texts.dart';
import 'package:bibelschul_app/services/auto_backup.dart';
import 'package:bibelschul_app/services/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

final _start = DateTime.utc(2026, 3, 2, 6).millisecondsSinceEpoch; // 07:00 in Berlin

ReadingState _plan({String start = '2026-03-02', int amount = 30, String order = 'canonical'}) => applyAction(
      null,
      {
        'action': 'create',
        'config': {
          'amount': amount,
          'unit': 'days',
          'start': start,
          'time': '07:30',
          'timezone': 'Europe/Berlin',
          'scope': 'nt',
          'order': order,
          'keepTogether': true,
          'bookOrderMode': 'auto',
        },
        'previouslyRead': <int>[],
        'lang': 'de',
        'planId': null,
        'opId': uuid(),
      },
      _start,
    );

ReadingState _act(ReadingState s, Map<String, Object?> op, int now) =>
    applyAction(s, {...op, 'planId': s.id, 'opId': uuid()}, now);

void main() {
  tzdata.initializeTimeZones();

  test('backups without notes stay web-compatible (version 8)', () {
    final s = _plan();
    final raw = makeAppBackup(s, Lang.de, 'light', const []);
    expect((jsonDecode(raw) as Map)['version'], 8);
    expect(parseBackup(raw).state.config.amount, 30); // the web parser accepts it
  });

  test('backups keep the reading-group access so a reinstall keeps the groups', () {
    final s = _plan();
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
    final raw = makeAppBackup(s, Lang.de, 'light', const [], null, (token: token, name: 'Tobi'));
    expect((jsonDecode(raw) as Map)['version'], 9);
    final restored = parseAppBackup(raw);
    expect(restored.groups?.token, token);
    expect(restored.groups?.name, 'Tobi');
    final broken = (jsonDecode(raw) as Map)..['groups'] = {'token': 'short', 'name': 'x'};
    expect(() => parseAppBackup(jsonEncode(broken)), throwsA(isA<AppError>()));
  });

  test('backups with notes use version 9 and restore the notes', () {
    final s = _plan();
    final note = ReadingNote(
        id: 'n1', planId: s.id, day: 0, date: '2026-03-02', passage: 'Matthäus 1–2', text: 'Gedanke', updatedAt: 1);
    final raw = makeAppBackup(s, Lang.de, 'dark', [note]);
    expect((jsonDecode(raw) as Map)['version'], 9);
    expect(() => parseBackup(raw), throwsA(isA<AppError>()), reason: 'old clients must not misread notes');
    final restored = parseAppBackup(raw);
    expect(restored.notes.single.text, 'Gedanke');
    expect(restored.backup.theme, 'dark');
    final merged = mergeRestoredNotes([], restored.notes, s.id, 'new-id');
    expect(merged.single.planId, 'new-id');
    final broken = (jsonDecode(raw) as Map)..['notes'] = [{'id': 'x'}];
    expect(() => parseAppBackup(jsonEncode(broken)), throwsA(isA<AppError>()));
  });

  test('plan codes carry settings only and survive chat text around them', () {
    final s = _plan(order: 'chronological');
    final code = encodePlanCode(s.config, 'Klasse 2026');
    expect(code, startsWith('LESEWEG1.'));
    final plan = decodePlanCode('Lies mit mir! $code Danke', time: '06:00', timezone: 'America/New_York')!;
    expect(plan.name, 'Klasse 2026');
    expect(plan.config.order, 'chronological');
    expect(plan.config.start, s.config.start);
    expect(plan.config.time, '06:00', reason: 'each reader keeps their own reminder time');
    expect(plan.config.timezone, 'America/New_York');
    expect(decodePlanCode('LESEWEG1.kaputt', time: '06:00', timezone: 'UTC'), isNull);
    expect(decodePlanCode('irgendein Text', time: '06:00', timezone: 'UTC'), isNull);
    final b52 = bible52Config(Config(amount: 1, unit: 'days', start: '2026-01-05', time: '07:30', timezone: 'UTC'));
    expect(isBible52(decodePlanCode(encodePlanCode(b52, ''), time: '07:00', timezone: 'UTC')!.config), isTrue);
  });

  test('reminders skip a day that is already read and add evening ones', () {
    var s = _plan();
    final morning = DateTime.utc(2026, 3, 2, 5); // 06:00 Berlin, before the 07:30 reminder
    final plan = Reminders.plan(s, evening: true, eveningTime: '20:00', now: morning);
    expect(plan.length, Reminders.days * 2);
    expect(plan.first.$1, DateTime.utc(2026, 3, 2, 6, 30));
    expect(plan[1], (DateTime.utc(2026, 3, 2, 19), true));
    // Read something today: today's reminders disappear, tomorrow's stay.
    final first = s.adaptive!.days[0].first;
    s = _act(s, {'action': 'chapter', 'chapter': first, 'done': true}, morning.millisecondsSinceEpoch);
    final after = Reminders.plan(s, evening: true, eveningTime: '20:00', now: morning);
    expect(after.first.$1, DateTime.utc(2026, 3, 3, 6, 30));
    expect(after.length, (Reminders.days - 1) * 2);
    // No evening option: only morning reminders.
    expect(Reminders.plan(s, evening: false, eveningTime: '20:00', now: morning).every((r) => !r.$2), isTrue);
  });

  test('a finished plan gets no reminders', () {
    final s = _plan();
    final all = [for (final c in scopeFor(s.config)) c.id];
    final done = _act(s, {'action': 'previous', 'previouslyRead': all}, _start);
    expect(planComplete(done), isTrue);
    expect(Reminders.plan(done, evening: true, eveningTime: '20:00', now: DateTime.utc(2026, 3, 2, 5)), isEmpty);
  });

  test('falling behind suggests moving the target by the missed days', () {
    final s = _plan(amount: 60);
    expect(behindSchedule(s, '2026-03-02'), isNull, reason: 'first day');
    final later = behindSchedule(s, '2026-03-12')!;
    final original = createPlan(s.config);
    expect(later.chapters, original.take(10).fold<int>(0, (n, d) => n + d.chapters.length));
    expect(later.days, (later.chapters / (260 / 60)).ceil());
    final moved = _act(s, {'action': 'deadline', 'end': addDays('2026-04-30', later.days)},
        DateTime.utc(2026, 3, 12, 8).millisecondsSinceEpoch);
    expect(duration(moved.config), 60 + later.days);
  });

  test('book progress counts chapters per book', () {
    final s = _plan();
    final matthew = scopeFor(s.config).where((c) => c.code == 'MAT').take(4).map((c) => c.id).toList();
    final read = _act(s, {'action': 'previous', 'previouslyRead': matthew}, _start);
    final books = bookProgress(read);
    expect(books.length, 27);
    expect(books.first, (39, 4, 28));
  });

  test('automatic backups keep one file per day and the latest ten', () async {
    final dir = Directory.systemTemp.createTempSync('leseweg-auto');
    final backups = AutoBackup(dir);
    final s = _plan();
    for (var i = 0; i < 14; i++) {
      await backups.write(s, Lang.de, 'light', const [], DateTime.utc(2026, 3, 2 + i, 12).millisecondsSinceEpoch);
    }
    await backups.write(s, Lang.de, 'light', const [], DateTime.utc(2026, 3, 15, 18).millisecondsSinceEpoch);
    final files = dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()..sort();
    expect(files.length, AutoBackup.keep);
    expect(files.last, 'leseweg-sicherung-2026-03-15.json');
    expect(files.first, 'leseweg-sicherung-2026-03-06.json');
    expect(parseAppBackup(File('${dir.path}/${files.last}').readAsStringSync()).backup.state.id, s.id);
  });

  test('all native texts exist in every language', () {
    final keys = featureText(Lang.de).t.keys.toSet();
    final genres = featureText(Lang.de).questions.keys.toSet();
    for (final lang in Lang.values) {
      expect(featureText(lang).t.keys.toSet(), keys, reason: lang.name);
      expect(featureText(lang).questions.keys.toSet(), genres, reason: lang.name);
      expect(featureText(lang).questions.values.every((q) => q.length == 3), isTrue);
    }
    expect({for (var i = 0; i < 66; i++) genreOfBook(i)}, genres);
  });
}
