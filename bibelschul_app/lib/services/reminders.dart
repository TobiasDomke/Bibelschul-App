import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/languages.dart';

/// Daily reading reminders, scheduled on the device itself.
///
/// The web app needed a Cloudflare push service for this. A native app can
/// schedule local notifications directly: they work offline and no reminder
/// data ever leaves the device. Like the web reminders, the message is general;
/// the chapters are calculated when the app opens.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _dailyId = 1;
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

  Future<void> scheduleDaily({required String time, required String timezone, required Lang lang}) async {
    await _init();
    await _plugin.cancel(id: _dailyId);
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Leseweg',
      body: _messages[lang]!.$1,
      scheduledDate: nextOccurrence(time, timezone),
      notificationDetails: _details,
      // Inexact delivery needs no special alarm permission on Android.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDaily() async {
    await _init();
    await _plugin.cancel(id: _dailyId);
  }

  Future<void> showTest(Lang lang) async {
    await _init();
    await _plugin.show(id: _testId, title: 'Leseweg', body: _messages[lang]!.$2, notificationDetails: _details);
  }
}
