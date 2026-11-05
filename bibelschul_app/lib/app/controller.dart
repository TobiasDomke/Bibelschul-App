import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/backup.dart';
import '../core/languages.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../services/preferences.dart';
import '../services/reminders.dart';
import '../services/storage.dart';

enum LoadStatus { loading, ready, error }

/// App-wide state; mirrors the state hooks of app/leseweg.tsx.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({required this.store, required this.prefs, required this.deviceZone, required Lang systemLang})
      : lang = prefs.lang ?? systemLang,
        theme = prefs.theme == 'dark' ? 'dark' : 'light';

  final ReadingStore store;
  final Preferences prefs;
  final String deviceZone;

  Lang lang;
  String theme;
  ReadingState? state;
  LoadStatus status = LoadStatus.loading;
  bool busy = false;

  /// "", "saved", "replanned", "deadline", "timerStopped"
  String message = '';

  /// "", "timer", "changed", "save"
  String error = '';
  String tab = 'today';
  int? selected;
  int page = 0;
  bool newPlan = false;
  int now = DateTime.now().millisecondsSinceEpoch;
  String reminderTime = '07:30';
  late String zone = deviceZone;
  Timer? _ticker;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = DateTime.now().millisecondsSinceEpoch;
      // A running timer needs every second; otherwise refresh for date changes.
      if (state?.timer != null || next ~/ 60000 != now ~/ 60000) {
        now = next;
        notifyListeners();
      }
    });
    await load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      now = DateTime.now().millisecondsSinceEpoch;
      if (!busy) unawaited(load(silent: true));
    }
  }

  Future<void> load({bool silent = false}) async {
    try {
      if (!silent) {
        status = LoadStatus.loading;
        notifyListeners();
      }
      final data = await store.read();
      state = data;
      status = LoadStatus.ready;
      if (data?.config.bookOrderMode != null) lang = data!.lang;
      if (data != null && !silent) {
        reminderTime = data.config.time;
        zone = data.config.timezone;
        if (data.config.bookOrderMode == null && prefs.lang == null) lang = data.lang;
      }
    } catch (_) {
      if (!silent) status = LoadStatus.error;
    }
    notifyListeners();
  }

  void setLang(Lang value) {
    lang = value;
    prefs.lang = value;
    notifyListeners();
  }

  void setTheme(String value) {
    theme = value;
    prefs.theme = value;
    notifyListeners();
  }

  void setTab(String value) {
    tab = value;
    notifyListeners();
  }

  void choose(int index) {
    selected = index;
    tab = 'today';
    notifyListeners();
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  Future<ReadingState?> mutate(Map<String, Object?> op) async {
    if (busy) return null;
    busy = true;
    error = '';
    message = '';
    notifyListeners();
    try {
      final updated = await store.change({...op, 'planId': state?.id, 'opId': uuid()});
      state = updated;
      now = DateTime.now().millisecondsSinceEpoch;
      await _syncReminder();
      return updated;
    } catch (e) {
      final code = e is AppError ? e.code : '';
      error = code == 'timer'
          ? 'timer'
          : ['day', 'finished', 'stale'].contains(code)
              ? 'changed'
              : 'save';
      unawaited(load(silent: true));
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> changeLanguage(Lang value) async {
    if (value == lang || busy) return;
    if (state == null) {
      setLang(value);
      return;
    }
    final updated = await mutate({'action': 'language', 'lang': value.name});
    if (updated != null) setLang(updated.lang);
  }

  void restored(ReadingState value, String newTheme) {
    state = value;
    lang = value.lang;
    prefs.lang = value.lang;
    setTheme(newTheme);
    reminderTime = value.config.time;
    zone = value.config.timezone;
    selected = null;
    page = 0;
    tab = 'today';
    newPlan = false;
    error = '';
    message = '';
    unawaited(_syncReminder());
    notifyListeners();
  }

  Future<ReadingState> restoreBackup(Backup backup) async {
    final restoredState = await store.restore(backup.state, state?.id);
    restored(restoredState, backup.theme);
    return restoredState;
  }

  /// Keeps the scheduled local reminder in line with the plan's time, zone and language.
  Future<void> _syncReminder() async {
    final s = state;
    if (!prefs.remindersEnabled || s == null) return;
    try {
      await Reminders.instance.scheduleDaily(time: s.config.time, timezone: s.config.timezone, lang: s.lang);
    } catch (_) {
      // Reminder scheduling must never block saving the reading plan.
    }
  }

  Future<bool> enableReminders() async {
    final s = state;
    if (s == null) return false;
    final allowed = await Reminders.instance.requestPermission();
    if (!allowed) return false;
    prefs.remindersEnabled = true;
    await Reminders.instance.scheduleDaily(time: s.config.time, timezone: s.config.timezone, lang: s.lang);
    notifyListeners();
    return true;
  }

  Future<void> disableReminders() async {
    prefs.remindersEnabled = false;
    await Reminders.instance.cancelDaily();
    notifyListeners();
  }
}
