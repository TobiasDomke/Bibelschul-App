import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/insights.dart';
import '../core/languages.dart';
import '../core/notes.dart';
import '../core/plan_code.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/feature_texts.dart';
import '../i18n/i18n.dart';
import '../services/auto_backup.dart';
import '../services/native_bridge.dart';
import '../services/preferences.dart';
import '../services/reminders.dart';
import '../services/storage.dart';
import 'plan_view.dart';

enum LoadStatus { loading, ready, error }

/// App-wide state; mirrors the state hooks of app/leseweg.tsx plus the
/// native-only features (notes, reminders, automatic backups, widget).
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required this.store,
    required this.prefs,
    required this.deviceZone,
    required Lang systemLang,
    this.autoBackups,
    this.native = true,
  })  : lang = prefs.lang ?? systemLang,
        theme = prefs.theme == 'dark' ? 'dark' : 'light';

  final ReadingStore store;
  final Preferences prefs;
  final String deviceZone;
  final AutoBackup? autoBackups;

  /// False in tests: no notifications, widget or live activity.
  final bool native;

  Lang lang;
  String theme;
  ReadingState? state;
  List<ReadingNote> notes = [];
  LoadStatus status = LoadStatus.loading;
  bool busy = false;

  /// "", "saved", "replanned", "deadline", "timerStopped", "note", "noteDeleted"
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
    unawaited(_syncDevice(null));
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
      if (!busy) unawaited(load(silent: true).then((_) => _syncDevice(null)));
    }
  }

  Future<void> load({bool silent = false}) async {
    try {
      if (!silent) {
        status = LoadStatus.loading;
        notifyListeners();
      }
      final data = await store.read();
      notes = await store.readNotes();
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
    // Status messages belong to the screen where the action happened.
    message = '';
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
    final before = state;
    try {
      final updated = await store.change({...op, 'planId': state?.id, 'opId': uuid()});
      state = updated;
      now = DateTime.now().millisecondsSinceEpoch;
      unawaited(_syncDevice(before, backup: op['action'] == 'complete'));
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

  /// Finishes the current unit in one step (the web app asked again in a dialog).
  Future<ReadingState?> finish(int day, {String? paceChoice}) async {
    final fixed = state?.config.template == 'bible52';
    final updated = await mutate({'action': 'complete', 'day': day, 'paceChoice': ?paceChoice});
    if (updated != null) {
      update(() {
        message = fixed ? 'saved' : 'replanned';
        selected = null;
      });
    }
    return updated;
  }

  /// "Read it all": checks every open chapter of the unit, then finishes it.
  Future<ReadingState?> readAll(int day, List<int> chapters, {String? paceChoice}) async {
    for (final id in chapters) {
      if (state?.done.containsKey(id) ?? true) continue;
      if (await mutate({'action': 'chapter', 'chapter': id, 'done': true}) == null) return null;
    }
    return finish(day, paceChoice: paceChoice);
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
    unawaited(_syncDevice(null));
    notifyListeners();
  }

  Future<ReadingState> restoreBackup(AppBackup backup) async {
    final restoredState = await store.restore(backup.backup.state, state?.id);
    notes = mergeRestoredNotes(notes, backup.notes, backup.backup.state.id, restoredState.id);
    await store.writeNotes(notes);
    restored(restoredState, backup.backup.theme);
    return restoredState;
  }

  /// Creates a plan received from a group (QR code or plan code).
  Future<ReadingState?> joinPlan(SharedPlan plan) async {
    final created = await mutate({
      'action': 'create',
      'config': (plan.config..time = reminderTime..timezone = zone).toJson(),
      'previouslyRead': <int>[],
      'lang': lang.name,
    });
    if (created != null) {
      prefs.setGroupName(created.id, plan.name);
      update(() {
        newPlan = false;
        selected = null;
        page = 0;
        tab = 'today';
      });
    }
    return created;
  }

  // ----- Notes -----

  ReadingNote? noteFor(int day) {
    final id = state?.id;
    for (final n in notes) {
      if (n.planId == id && n.day == day) return n;
    }
    return null;
  }

  Future<void> saveNote({required int day, required String date, required String passage, required String text}) async {
    final s = state;
    if (s == null) return;
    final trimmed = text.trim();
    final existing = noteFor(day);
    if (trimmed.isEmpty) {
      if (existing != null) await deleteNote(existing.id);
      return;
    }
    final at = DateTime.now().millisecondsSinceEpoch;
    if (existing != null) {
      existing
        ..text = trimmed.length > maxNoteLength ? trimmed.substring(0, maxNoteLength) : trimmed
        ..passage = passage
        ..updatedAt = at;
    } else {
      notes = [
        ReadingNote(
          id: uuid(),
          planId: s.id,
          day: day,
          date: date,
          passage: passage,
          text: trimmed.length > maxNoteLength ? trimmed.substring(0, maxNoteLength) : trimmed,
          updatedAt: at,
        ),
        ...notes,
      ];
    }
    await store.writeNotes(notes);
    update(() => message = 'note');
  }

  Future<void> deleteNote(String id) async {
    notes = notes.where((n) => n.id != id).toList();
    await store.writeNotes(notes);
    update(() => message = 'noteDeleted');
  }

  // ----- Reminders -----

  Future<bool> enableReminders() async {
    if (state == null) return false;
    final allowed = !native || await Reminders.instance.requestPermission();
    if (!allowed) return false;
    prefs.remindersEnabled = true;
    await _syncReminders();
    notifyListeners();
    return true;
  }

  Future<void> disableReminders() async {
    prefs.remindersEnabled = false;
    if (native) await Reminders.instance.cancelAll();
    notifyListeners();
  }

  Future<void> setEvening({bool? enabled, String? time}) async {
    if (enabled != null) prefs.eveningReminder = enabled;
    if (time != null) prefs.eveningTime = time;
    await _syncReminders();
    notifyListeners();
  }

  void setAutoBackup(bool enabled) {
    prefs.autoBackup = enabled;
    notifyListeners();
  }

  Future<void> _syncReminders() async {
    final s = state;
    if (!native || !prefs.remindersEnabled || s == null) return;
    try {
      await Reminders.instance.schedule(s, evening: prefs.eveningReminder, eveningTime: prefs.eveningTime);
    } catch (_) {
      // Reminder scheduling must never block saving the reading plan.
    }
  }

  /// Reminders, automatic backup, home-screen widget and lock-screen timer
  /// follow every change. None of them may block or fail a reading action.
  Future<void> _syncDevice(ReadingState? before, {bool backup = false}) async {
    final s = state;
    await _syncReminders();
    if (s == null) return;
    if (backup && prefs.autoBackup && autoBackups != null) {
      try {
        await autoBackups!.write(s, lang, theme, notes);
        prefs.lastAutoBackup = DateTime.now().millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (!native) return;
    final v = PlanView.of(this);
    if (v != null) {
      final t = text(lang), f = featureText(lang);
      final done = readOn(s, v.currentDate);
      final today = v.days[v.dateIndex.clamp(0, v.days.length - 1)];
      await NativeBridge.instance.updateWidget(
        title: done ? f['widgetDone'] : t.today,
        passage: v.readLabel(v.fixed ? today.chapters : v.sessionItemsFor(v.dateIndex)),
        detail: v.fixed ? bible52Position(v.dateIndex, lang) : '${t.day} ${v.dateIndex + 1} / ${v.days.length}',
        progress: v.percent / 100,
        done: done,
      );
      final timer = s.timer;
      if (timer != null && before?.timer == null) {
        await NativeBridge.instance.startTimer(
          startedAt: timer.startedAt,
          title: f['liveTimer'],
          passage: v.readLabel(v.sessionItemsFor(timer.day)),
        );
      } else if (timer == null && before?.timer != null) {
        await NativeBridge.instance.stopTimer();
      }
    }
  }
}
