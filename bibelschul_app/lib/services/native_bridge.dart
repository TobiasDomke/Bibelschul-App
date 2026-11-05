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

  /// Data shown by the home-screen widget.
  Future<void> updateWidget({
    required String title,
    required String passage,
    required String detail,
    required double progress,
    required bool done,
  }) =>
      _call('updateWidget', {
        'title': title,
        'passage': passage,
        'detail': detail,
        'progress': progress,
        'done': done,
      });

  /// Lock-screen timer counting up from [startedAt] (ms since epoch).
  Future<void> startTimer({required int startedAt, required String title, required String passage}) =>
      _call('startTimer', {'startedAt': startedAt, 'title': title, 'passage': passage});

  Future<void> stopTimer() => _call('stopTimer');
}
