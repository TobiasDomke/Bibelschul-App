import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/insights.dart';
import '../core/languages.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/feature_texts.dart';

/// Daily reading reminders, scheduled on the device itself.
///
/// The web app needed a Cloudflare push service for this. A native app can
/// schedule local notifications directly: they work offline and no reminder
/// data leaves the device. Instead of one repeating notification, the next
/// [days] days are scheduled individually, so a day on which the reader has
/// already read gets no reminder, and an optional evening reminder only comes
/// when nothing was read yet. The schedule is rebuilt after every change and
/// whenever the app opens.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const days = 28; // 2 × 28 stays below iOS's limit of 64 pending notifications.
  static const _testId = 2;

  static const _messages = {
    Lang.de: (
      'Zeit zum Bibellesen. Öffne Leseweg für deine heutigen Kapitel.',
      'Deine Testnachricht ist angekommen. Die tägliche Erinnerung ist bereit.'
    ),
    Lang.ru: (
      'Время читать Библию. Открой Leseweg, чтобы увидеть главы на сегодня.',
      'Проверочное уведомление доставлено. Ежедневные напоминания готовы.'
    ),
    Lang.en: (
      "Time to read your Bible. Open Leseweg for today's chapters.",
      'Your test notification has arrived. Daily reminders are ready.'
    ),
    Lang.uk: (
      'Час читати Біблію. Відкрий Leseweg, щоб побачити розділи на сьогодні.',
      'Тестове сповіщення надійшло. Щоденні нагадування готові.'
    ),
  };

  Future<void> _init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'leseweg-daily',
          'Leseweg',
          channelDescription: 'Tägliche Bibellese-Erinnerung',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Asks the system for permission. Returns false when the user declined.
  Future<bool> requestPermission() async {
    await _init();
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    return false;
  }

  /// Next occurrence of [time] (HH:MM) in [timezone], strictly after now.
  static tz.TZDateTime nextOccurrence(String time, String timezone, [DateTime? now]) {
    final location = timezone == 'UTC' ? tz.UTC : tz.getLocation(timezone);
    final current = tz.TZDateTime.from(now ?? DateTime.now(), location);
    final [h, m] = time.split(':').map(int.parse).toList();
    var due = tz.TZDateTime(location, current.year, current.month, current.day, h, m);
    if (!due.isAfter(current)) due = tz.TZDateTime(location, current.year, current.month, current.day + 1, h, m);
    return due;
  }

  /// The reminders to schedule from [now] on: (instant, evening?).
  /// Pure function, so the skipping rules can be tested without a device.
  static List<(DateTime, bool)> plan(
    ReadingState state, {
    required bool evening,
    required String eveningTime,
    DateTime? now,
  }) {
    if (planComplete(state)) return const [];
    final at = now ?? DateTime.now();
    final zone = state.config.timezone;
    final todayDate = today(zone, at.millisecondsSinceEpoch);
    final readToday = readOn(state, todayDate);
    final result = <(DateTime, bool)>[];
    for (var i = 0; i < days; i++) {
      final date = addDays(todayDate, i);
      if (i == 0 && readToday) continue;
      for (final (time, isEvening) in [(state.config.time, false), if (evening) (eveningTime, true)]) {
        final instant = zonedUTC(date, time, zone);
        if (instant.isAfter(at)) result.add((instant, isEvening));
      }
    }
    return result;
  }

  Future<void> schedule(ReadingState state, {required bool evening, required String eveningTime}) async {
    await _init();
    await _plugin.cancelAll();
    final texts = featureText(state.lang);
    final location = state.config.timezone == 'UTC' ? tz.UTC : tz.getLocation(state.config.timezone);
    for (final (i, (instant, isEvening)) in plan(state, evening: evening, eveningTime: eveningTime).indexed) {
      await _plugin.zonedSchedule(
        id: 100 + i,
        title: 'Leseweg',
        body: isEvening ? texts['eveningMessage'] : _messages[state.lang]!.$1,
        scheduledDate: tz.TZDateTime.from(instant, location),
        notificationDetails: _details,
        // Inexact delivery needs no special alarm permission on Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }

  Future<void> showTest(Lang lang) async {
    await _init();
    await _plugin.show(id: _testId, title: 'Leseweg', body: _messages[lang]!.$2, notificationDetails: _details);
  }
}
