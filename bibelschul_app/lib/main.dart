import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app/controller.dart';
import 'core/languages.dart';
import 'core/util.dart';
import 'services/auto_backup.dart';
import 'services/preferences.dart';
import 'services/storage.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await initializeDateFormatting();
  String zone;
  try {
    zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (!isValidTimezone(zone)) zone = 'Europe/Berlin';
  } catch (_) {
    zone = 'Europe/Berlin';
  }
  final controller = AppController(
    store: await ReadingStore.open(),
    prefs: await Preferences.open(),
    deviceZone: zone,
    autoBackups: await AutoBackup.open(),
    systemLang: browserLanguage(WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag()),
  );
  runApp(LesewegApp(controller: controller));
  await controller.start();
}

class LesewegApp extends StatelessWidget {
  const LesewegApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final lang = controller.lang;
          final [language, country] = locales[lang]!.split('_');
          return MaterialApp(
            title: 'Leseweg',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: controller.theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
            locale: Locale(language, country),
            supportedLocales: const [Locale('de', 'DE'), Locale('ru', 'RU'), Locale('en', 'GB'), Locale('uk', 'UA')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Home(c: controller),
          );
        },
      );
}
