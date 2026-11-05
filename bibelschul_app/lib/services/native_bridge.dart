import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to native iOS code for the home-screen widget and the lock-screen
/// timer (Live Activity). Missing on other platforms: calls do nothing.
class NativeBridge {
  NativeBridge._();
  static final instance = NativeBridge._();
  static const _channel = MethodChannel('leseweg/native');

  Future<void> _call(String method, [Object? args]) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // Not available (tests, other platforms).
    } on PlatformException {
      // A widget or activity that cannot update must never block the app.
    }
  }

  /// Data shown by the home-screen widget. [date] is the local reading date;
  /// after midnight the widget switches to [nextPassage] until the app opens.
  Future<void> updateWidget({
    required String date,
    required String title,
    required String todayTitle,
    required String passage,
    required String detail,
    required String nextPassage,
    required String nextDetail,
    required double progress,
    required bool done,
  }) =>
      _call('updateWidget', {
        'date': date,
        'title': title,
        'todayTitle': todayTitle,
        'passage': passage,
        'detail': detail,
        'nextPassage': nextPassage,
        'nextDetail': nextDetail,
        'progress': progress,
        'done': done,
      });

  /// Lock-screen timer counting up from [startedAt] (ms since epoch).
  Future<void> startTimer({required int startedAt, required String title, required String passage}) =>
      _call('startTimer', {'startedAt': startedAt, 'title': title, 'passage': passage});

  Future<void> stopTimer() => _call('stopTimer');
}
