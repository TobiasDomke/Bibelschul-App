import 'dart:math';

import 'package:intl/intl.dart';

import '../core/actions.dart';
import '../core/adaptive.dart';
import '../core/languages.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/reading_time.dart';
import '../core/session_stats.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'controller.dart';

/// Formatting helpers matching the web app's toLocaleDateString calls.
class Fmt {
  Fmt(this.lang);
  final Lang lang;
  String get locale => locales[lang]!;

  String date(String iso, {bool long = false}) {
    final d = dateAt(iso);
    return (long ? DateFormat.yMMMMd(locale) : DateFormat.MMMd(locale)).format(DateTime(d.year, d.month, d.day));
  }

  String weekday(String iso) {
    final d = dateAt(iso);
    return DateFormat.E(locale).format(DateTime(d.year, d.month, d.day));
  }

  String month(String iso) {
    final d = dateAt(iso);
    return DateFormat.MMM(locale).format(DateTime(d.year, d.month, d.day));
  }

  String number(num value) => NumberFormat.decimalPattern(locale).format(value);

  String dateTime(int ms) =>
      DateFormat.yMd(locale).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(ms));

  String time(num seconds) => readingTime(seconds, lang);
}

/// Values derived from the current reading state; mirrors the computations
/// at the top of app/leseweg.tsx so all tabs show the same numbers.
class PlanView {
  PlanView._(this.c, this.state);
  final AppController c;
  final ReadingState state;

  late final Lang lang = c.lang;
  late final int now = c.now;
  late final bool fixed = isBible52(state.config);
  late final String currentDate = today(state.config.timezone, now);
  late final ReadingState planState = prepareState(state, currentDate);
  late final List<Day> days = readingPlan(planState, currentDate);
  late final ReadingPace pace = readingPace(state);
  late final ReadingTimeSummary timeSummary = readingTimeSummary(state, now, pace);
  late final int dateIndex = fixed ? bible52CurrentUnit(planState) : dayIndex(planState.config, currentDate);
  late final List<Chapter> scoped = scopeFor(state.config);
  late final int totalWords = scoped.fold(0, (s, c) => s + c.words);
  late final List<int> priorIds = state.previouslyRead ?? [];
  late final List<Chapter> inventory = chaptersFor(state.config.edition);
  late final List<Session> sessions = sessionsFor(state);
  late final Map<String, int> chartValues = dailySeconds(state, now);
  late final List<String>? names = bookNames(fixed ? Lang.de : lang);

  late final Day day = days[max(0, min(days.length - 1, c.selected ?? state.timer?.day ?? dateIndex))];

  /// Chapters read, including previously read ones (value "previous").
  late final Map<int, String> doneSet = {for (final id in priorIds) id: 'previous', ...state.done};
  late final int doneCount = doneSet.length;
  late final int readWords = scoped.where((ch) => doneSet.containsKey(ch.id)).fold(0, (s, ch) => s + ch.words);
  late final double percent = jsRound(readWords / totalWords * 1000) / 10;
  late final int totalSeconds = timeSummary.measuredSeconds;
  late final List<Session> timedSessions = sessions.where((s) => s.seconds > 0).toList();
  late final double averageSession =
      timedSessions.isEmpty ? 0 : timedSessions.fold<int>(0, (n, s) => n + s.seconds) / timedSessions.length;

  late final int seconds = daySeconds(state, day.index, now);
  late final bool running = state.timer?.day == day.index;
  late final bool dayDone = planState.adaptive?.finished.contains(day.index) ?? false;
  late final bool canRead = fixed
      ? (state.timer?.day ?? state.pace?.draft?.day ?? day.index) == day.index
      : day.index == dateIndex || running;
  late final List<Chapter> sessionItems = sessionChapters(planState, day.index);
  late final Set<int> extraIds = {...?planState.adaptive?.extra[day.index]};
  late final Chapter? nextExtra = nextExtraChapter(planState, day.index);
  late final int remainingWords = totalWords - readWords;
  late final int remainingDays = max(0, days.length - dateIndex - 1);
  late final int remainingChapters = scoped.length - doneCount;
  late final int sessionSeconds = canRead && !dayDone
      ? max(
          0,
          seconds -
              (state.pace?.draft?.day == day.index
                  ? state.pace!.draft!.secondsBefore
                  : sessions.where((s) => s.day == day.index).fold<int>(0, (n, s) => n + s.seconds)))
      : seconds;

  late final PaceSample? pendingSample = () {
    final draft = state.pace?.draft;
    if (draft == null) return null;
    return PaceSample(
      day: draft.day,
      chapters: state.done.keys.where((id) => !draft.before.contains(id)).toList(),
      seconds: max(0, daySeconds(state, draft.day, now) - draft.secondsBefore),
    );
  }();
  late final bool unusual = pendingSample != null && sampleNeedsReview(pendingSample!, state, pace.secondsPerWord);

  String readLabel(List<Chapter> items) => passage(items, names).isEmpty ? text(lang).rest : passage(items, names);

  /// Preview of the pace after finishing, using exactly the calculation saving commits.
  ReadingPace finishingPace(bool confirm) {
    try {
      return readingPace(applyAction(
          state,
          {
            'action': 'complete',
            if (confirm) 'paceChoice': 'confirmed',
            'day': day.index,
            'planId': state.id,
            'opId': uuid(),
          },
          now));
    } catch (_) {
      return pace;
    }
  }

  bool get backupDue {
    final history = c.prefs.backupStatus(state.id);
    return (sessions.length >= 3 ||
            (state.done.isNotEmpty && now - dateAt(state.config.start).millisecondsSinceEpoch > 7 * 86400000)) &&
        now - max(history.exported, history.snoozed) > 7 * 86400000;
  }

  static PlanView? of(AppController c) => c.state == null ? null : PlanView._(c, c.state!);
}
