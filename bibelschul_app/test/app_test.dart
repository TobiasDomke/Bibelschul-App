// Drives the real app UI: create a plan, read, time and finish a session.
// Screenshots: flutter test test/app_test.dart --update-goldens (written to test/goldens/).
import 'dart:io';

import 'package:bibelschul_app/app/controller.dart';
import 'package:bibelschul_app/core/languages.dart';
import 'package:bibelschul_app/core/plan_code.dart';
import 'package:bibelschul_app/main.dart';
import 'package:bibelschul_app/services/preferences.dart';
import 'package:bibelschul_app/services/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

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

Future<AppController> _controller(Directory dir, {Lang lang = Lang.de}) async {
  SharedPreferences.setMockInitialValues({});
  return AppController(
    store: ReadingStore(dir),
    prefs: await Preferences.open(),
    deviceZone: 'Europe/Berlin',
    systemLang: lang,
    native: false,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder, {bool real = false}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (real) {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
  } else {
    await tester.tap(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting();
    await _loadFonts();
  });

  testWidgets('create a plan, read chapters with the timer and finish the unit', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('leseweg-test');
    late AppController c;
    await tester.runAsync(() async {
      c = await _controller(dir);
    });
    await tester.pumpWidget(LesewegApp(controller: c));
    await tester.runAsync(c.start);
    await tester.pumpAndSettle();

    // Setup wizard.
    expect(find.text('Was möchtest du lesen?'), findsOneWidget);
    await _shot(tester, '01-setup');
    await _tap(tester, find.text('Eigenen Plan zusammenstellen'));
    await _shot(tester, '01b-setup-custom');
    await _tap(tester, find.widgetWithText(FilledButton, 'Weiter'));
    await _shot(tester, '02-setup-previous');
    await _tap(tester, find.widgetWithText(FilledButton, 'Weiter'));
    await _shot(tester, '03-setup-period');
    await _tap(tester, find.widgetWithText(FilledButton, 'Plan starten'), real: true);
    expect(c.state, isNotNull);
    expect(find.textContaining('Tag 1 /'), findsOneWidget);
    await _shot(tester, '04-today');

    // Start the timer, check the first chapter, pause.
    await _tap(tester, find.widgetWithText(FilledButton, 'Timer starten'), real: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
    expect(c.state!.timer, isNotNull);
    await _tap(tester, find.byType(CheckboxListTile).first, real: true);
    expect(c.state!.done.length, 1);
    await _shot(tester, '05-today-running');

    // Finish in one step. A one-second measurement is unusual, so the app asks
    // only whether it should train the forecast.
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Nur 1 abgehakte speichern'), real: true);
    expect(find.text('Stimmt diese Lesezeit?'), findsOneWidget);
    await _shot(tester, '06-unusual-measurement');
    await _tap(tester, find.widgetWithText(TextButton, 'Nein, nicht mitzählen'), real: true);
    expect(c.state!.timer, isNull);
    expect(c.state!.sessions, hasLength(1));
    expect(c.state!.adaptive!.finished, contains(0));
    expect(c.state!.pace!.samples.single.review, 'excluded');
    // The saved message names the chapters that moved to the next days.
    expect(find.textContaining('nicht gelesene Kapitel'), findsOneWidget);

    // A note for the finished unit.
    await _tap(tester, find.widgetWithText(TextButton, 'Gedanken notieren'));
    await tester.enterText(find.byType(TextField), 'Am Anfang schuf Gott – alles beginnt bei ihm.');
    await _shot(tester, '06b-note-editor');
    await _tap(tester, find.widgetWithText(FilledButton, 'Speichern'), real: true);
    expect(c.notes.single.text, startsWith('Am Anfang'));
    await _shot(tester, '06c-today-with-note');

    // The other tabs.
    for (final (label, name) in [
      ('Leseplan', '07-plan'),
      ('Notizen', '07b-notes'),
      ('Statistik', '08-stats'),
      ('Einstellungen', '09-settings'),
    ]) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      await _shot(tester, name);
    }

    // Reading groups live next to the own statistics.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Statistik')));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Gruppen'));
    await _shot(tester, '08b-groups-intro');
    await _tap(tester, find.text('Meine Zahlen'));

    // A plan day opens as a sheet instead of leaving the plan.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Leseplan')));
    await tester.pumpAndSettle();
    await _tap(tester, find.descendant(of: find.byType(CircleAvatar), matching: find.text('3')));
    await _shot(tester, '07c-plan-day');
    await tester.tapAt(const Offset(20, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Einstellungen')));
    await tester.pumpAndSettle();

    // Settings groups open their own pages.
    await _tap(tester, find.text('Erinnerungen'));
    await _shot(tester, '09b-settings-reminders');
    await _tap(tester, find.byType(BackButton));
    await _tap(tester, find.widgetWithText(ListTile, 'Leseplan'));
    await _tap(tester, find.widgetWithText(FilledButton, 'QR-Code anzeigen'));
    await _shot(tester, '09c-share-qr');
    await _tap(tester, find.widgetWithText(TextButton, 'Schließen'));
    await _tap(tester, find.byType(BackButton));

    // Dark mode and another language.
    c.setTheme('dark');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Heute')));
    await tester.pumpAndSettle();
    await _shot(tester, '10-today-dark');
    await tester.runAsync(() => c.changeLanguage(Lang.uk));
    await tester.pumpAndSettle();
    expect(c.state!.lang, Lang.uk);
    await _shot(tester, '11-today-uk');

    // Data survives a restart of the app.
    final id = c.state!.id;
    c.dispose();
    late AppController again;
    await tester.runAsync(() async {
      again = AppController(
          store: ReadingStore(dir),
          prefs: await Preferences.open(),
          deviceZone: 'Europe/Berlin',
          systemLang: Lang.de,
          native: false);
      await again.load();
    });
    expect(again.state!.id, id);
    expect(again.state!.done.length, 1);
    await tester.pumpWidget(const SizedBox());
    again.dispose();
  });

  testWidgets('Bibelleseplan 52 opens the first unit', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('leseweg-test52');
    late AppController c;
    await tester.runAsync(() async {
      c = await _controller(dir);
    });
    await tester.pumpWidget(LesewegApp(controller: c));
    await tester.runAsync(c.start);
    await tester.pumpAndSettle();
    // Quick-start template: one tap fills the plan and jumps to the preview.
    await _tap(tester, find.text('Bibelleseplan 52'));
    await _shot(tester, '12a-bible52-setup');
    await _tap(tester, find.widgetWithText(FilledButton, 'Plan starten'), real: true);
    expect(c.state!.config.template, 'bible52');
    expect(find.textContaining('Woche 1'), findsWidgets);
    await _shot(tester, '12-bible52-today');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Leseplan')));
    await tester.pumpAndSettle();
    await _shot(tester, '13-bible52-plan');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('template, "read it all" and joining a group plan', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('leseweg-test-nt');
    late AppController c;
    await tester.runAsync(() async {
      c = await _controller(dir);
    });
    await tester.pumpWidget(LesewegApp(controller: c));
    await tester.runAsync(c.start);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Neues Testament in 90 Tagen'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Plan starten'), real: true);
    expect(c.state!.config.scope, 'nt');
    expect(c.state!.config.amount, 90);
    final today = c.state!.adaptive!.days[0];
    await _tap(tester, find.widgetWithText(FilledButton, 'Alles gelesen – abschließen'), real: true);
    expect(today.every(c.state!.done.containsKey), isTrue);
    expect(c.state!.adaptive!.finished, contains(0));
    await _shot(tester, '14-read-all');

    // Join a plan shared by a group: same settings, new plan, group name shown.
    final code = encodePlanCode(c.state!.config..order = 'chronological', 'Bibelschule 2026');
    final shared = decodePlanCode(code, time: '06:30', timezone: 'Europe/Berlin')!;
    await tester.runAsync(() => c.joinPlan(shared));
    await tester.pumpAndSettle();
    expect(c.state!.config.order, 'chronological');
    expect(c.state!.done, isEmpty);
    expect(find.textContaining('Bibelschule 2026'), findsOneWidget);
    await _shot(tester, '15-group-plan');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
