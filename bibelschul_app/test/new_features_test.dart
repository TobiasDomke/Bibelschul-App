// Reading groups, texts and the small helpers of the reworked screens.
import 'dart:io';

import 'package:bibelschul_app/app/controller.dart';
import 'package:bibelschul_app/app/groups.dart';
import 'package:bibelschul_app/app/plan_view.dart';
import 'package:bibelschul_app/app/reading_stats.dart';
import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/languages.dart';
import 'package:bibelschul_app/core/planner.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/i18n/app_texts.dart';
import 'package:bibelschul_app/main.dart';
import 'package:bibelschul_app/services/groups_api.dart';
import 'package:bibelschul_app/services/preferences.dart';
import 'package:bibelschul_app/services/storage.dart';
import 'package:bibelschul_app/ui/small_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// In-memory stand-in for the group service.
class FakeApi extends GroupsApi {
  FakeApi(super.token, this.server);
  final Map<String, Map<String, Object?>> server;
  int updates = 0;
  MemberStats? lastStats;

  Map<String, Object?> _view(String id, String name, MemberStats? stats) => {
        'id': id,
        'name': server[id]!['name'],
        'code': 'ABCD-EFGH',
        'createdAt': 0,
        'owner': true,
        'me': {'memberId': 'm1', 'name': name, 'visible': true},
        'hiddenCount': 1,
        'members': [
          {'memberId': 'm1', 'name': name, 'owner': true, 'me': true, 'stats': stats?.toJson(), 'updatedAt': 1},
          {
            'memberId': 'm2',
            'name': 'Anna',
            'owner': false,
            'me': false,
            'stats': const MemberStats(
                    chapters: 40, total: 1189, weekChapters: 9, streak: 6, minutes: 120, wpm: 210, lastRead: '2026-11-04', plan: 'Gesamte Bibel')
                .toJson(),
            'updatedAt': 1,
          },
          {'memberId': 'm3', 'name': 'Ben', 'owner': false, 'me': false, 'stats': null, 'updatedAt': 1},
        ],
      };

  @override
  Future<ReadingGroup> create(String groupName, String name, MemberStats? stats, bool visible) async {
    server['g1'] = {'name': groupName};
    lastStats = stats;
    return ReadingGroup.fromJson(_view('g1', name, stats));
  }

  @override
  Future<ReadingGroup> join(String code, String name, MemberStats? stats, bool visible) async {
    if (code != 'ABCD-EFGH') throw const GroupsError('group_not_found');
    return create('Klasse', name, stats, visible);
  }

  @override
  Future<List<String>> list() async => server.keys.toList();

  @override
  Future<ReadingGroup> get(String id) async => ReadingGroup.fromJson(_view(id, 'Tobi', lastStats));

  @override
  Future<void> updateMe(String name, MemberStats? stats) async {
    updates++;
    lastStats = stats;
  }

  @override
  Future<void> leave(String id) async => server.remove(id);
}

Future<void> _loadFonts() async {
  // Real glyphs instead of the test font, so screenshots are readable.
  final candidates = [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  ];
  for (final family in ['Roboto', '.SF UI Text', '.SF Pro Text']) {
    final loader = FontLoader(family);
    for (final path in candidates) {
      if (File(path).existsSync()) loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting();
    await _loadFonts();
  });

  test('every text exists in every language with the same placeholders', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final MapEntry(key: lang, value: table) in uiTextTables.entries) {
      for (final key in uiTextKeys) {
        expect(table.containsKey(key), isTrue, reason: '$lang: $key');
        final want = placeholder.allMatches(uiTextTables[Lang.de]![key]!).map((m) => m[1]).toSet();
        final have = placeholder.allMatches(table[key]!).map((m) => m[1]).toSet();
        expect(have, want, reason: '$lang: $key');
      }
      expect(table.keys.toSet().difference(uiTextKeys.toSet()), isEmpty, reason: '$lang has extra keys');
    }
  });

  test('invitation codes are found in typing, messages and links', () {
    expect(parseGroupCode('abcd efgh'), 'ABCD-EFGH');
    expect(parseGroupCode('ABCDEFGH'), 'ABCD-EFGH');
    expect(parseGroupCode('Lies mit uns! Code: K7MQ-X2PB\nhttps://leseweg.pages.dev/#gruppe=K7MQ-X2PB'), 'K7MQ-X2PB');
    expect(parseGroupCode('https://leseweg.pages.dev/#gruppe=k7mq-x2pb'), 'K7MQ-X2PB');
    expect(parseGroupCode('ABCD-EFG'), isNull);
    expect(parseGroupCode('ABCD-EFG1'), isNull, reason: '1 is not in the alphabet');
    expect(parseGroupCode('LESEWEG1.eyJjIjp7fX0'), isNull);
  });

  test('percent, streak and balanced-day order', () {
    expect(formattedPercent(0, Lang.de), '0,00');
    expect(formattedPercent(0.2691, Lang.de), '0,26');
    expect(formattedPercent(0.001, Lang.de), '0,01');
    expect(formattedPercent(3.479, Lang.de), '3,47');
    expect(formattedPercent(42.1, Lang.de), '42,10');
    expect(formattedPercent(99.999, Lang.de), '99,99');
    expect(formattedPercent(100, Lang.de), '100,00');
    expect(formattedPercent(3.479, Lang.en), '3.47');

    final config = parseConfig({
      'amount': 12, 'unit': 'months', 'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin',
      'scope': 'bible', 'order': 'mixed', 'keepTogether': true,
    });
    final all = scopeFor(config);
    final gen3 = all.firstWhere((c) => c.bookIndex == 0 && c.number == 3);
    final gen4 = all.firstWhere((c) => c.bookIndex == 0 && c.number == 4);
    final mat2 = all.firstWhere((c) => c.bookIndex == 39 && c.number == 2);
    expect(passage(displayOrder([gen3, mat2, gen4], config)), passage([gen3, gen4, mat2]));
    expect(displayOrder([gen3, mat2, gen4], config..order = 'chronological'), [gen3, mat2, gen4]);
  });

  test('streak counts days in a row up to today or yesterday', () {
    final state = ReadingState.fromJson({
      'version': 9, 'id': 'x', 'lang': 'de', 'updatedAt': '2026-11-05T00:00:00Z',
      'config': {'amount': 1, 'unit': 'months', 'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin'},
      'done': {'1': '2026-11-02', '2': '2026-11-03', '3': '2026-11-04'},
      'logs': [],
      'ops': [],
    });
    expect(readingStreak(state, '2026-11-05'), 3);
    expect(readingStreak(state, '2026-11-04'), 3);
    expect(readingStreak(state, '2026-11-07'), 0);
    expect(chaptersThisWeek(state, '2026-11-05'), 3);
    expect(lastReadDate(state), '2026-11-04');
  });

  testWidgets('a group: create, compare and share fresh numbers', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('leseweg-groups');
    final server = <String, Map<String, Object?>>{};
    late FakeApi api;
    late AppController c;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppController(
        store: ReadingStore(dir),
        prefs: await Preferences.open(),
        deviceZone: 'Europe/Berlin',
        systemLang: Lang.de,
        native: false,
      );
    });
    c.groups = GroupsController(c.prefs.store, api: (token) {
      expect(token, hasLength(43));
      return api = FakeApi(token, server);
    });
    await tester.pumpWidget(LesewegApp(controller: c));
    await tester.runAsync(c.start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ganze Bibel in 1 Jahr'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Plan starten'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Plan starten'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(c.state, isNotNull);

    final ok = await tester.runAsync(() => c.groups.create('Bibelschule Klasse 2', 'Tobi', PlanView.of(c)));
    expect(ok, isTrue);
    expect(api.lastStats!.total, 1189);
    expect(c.groups.groups.single.name, 'Bibelschule Klasse 2');

    c.update(() {
      c.tab = 'stats';
      c.statsView = 'groups';
    });
    await tester.pumpAndSettle();
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('1 verborgen', findRichText: true), findsNothing);
    expect(find.textContaining('1 verborgen'), findsOneWidget);

    // Ranking by speed puts Anna first and members without numbers last.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tempo'));
    await tester.pumpAndSettle();
    expect(find.text('210 W./Min.'), findsOneWidget);

    // Finishing a unit shares the new numbers in the background.
    final before = api.updates;
    await tester.runAsync(() => c.groups.pushStats(PlanView.of(c)));
    expect(api.updates, before + 1);

    // Leaving removes the group locally.
    await tester.runAsync(() => c.groups.leave(c.groups.groups.single));
    expect(c.groups.joined, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
