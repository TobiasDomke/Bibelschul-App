import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'languages.dart';

// JSON layout is identical to the web app (lib/state.ts), so backups move freely
// between the Leseweg web app and this app. Numeric-key records keep JS order
// (ascending numeric keys) via SplayTreeMap.

typedef IntKeyMap<V> = SplayTreeMap<int, V>;

IntKeyMap<V> _intMap<V>(Object? json, V Function(Object?) value) {
  final result = SplayTreeMap<int, V>();
  (json as Map).forEach((k, v) => result[int.parse(k as String)] = value(v));
  return result;
}

Map<String, Object?> _strMap<V>(Map<int, V> map, Object? Function(V) value) =>
    {for (final e in map.entries) '${e.key}': value(e.value)};

List<int> _ints(Object? json) => [for (final v in json as List) (v as num).toInt()];

class Config {
  String? template; // "bible52"
  String? edition;
  int amount;
  String unit; // days | weeks | months
  String start;
  String time;
  String timezone;
  String? scope; // bible | ot | nt
  String? order; // canonical | chronological | mixed
  bool? keepTogether;
  String? bookOrder; // western | eastern
  String? bookOrderMode; // auto | manual

  Config({
    this.template,
    this.edition,
    required this.amount,
    required this.unit,
    required this.start,
    required this.time,
    required this.timezone,
    this.scope,
    this.order,
    this.keepTogether,
    this.bookOrder,
    this.bookOrderMode,
  });

  factory Config.fromJson(Map<String, Object?> j) => Config(
        template: j['template'] as String?,
        edition: j['edition'] as String?,
        amount: (j['amount'] as num).toInt(),
        unit: j['unit'] as String,
        start: j['start'] as String,
        time: j['time'] as String,
        timezone: j['timezone'] as String,
        scope: j['scope'] as String?,
        order: j['order'] as String?,
        keepTogether: j['keepTogether'] as bool?,
        bookOrder: j['bookOrder'] as String?,
        bookOrderMode: j['bookOrderMode'] as String?,
      );

  Map<String, Object?> toJson() => {
        if (template != null) 'template': template,
        if (edition != null) 'edition': edition,
        'amount': amount,
        'unit': unit,
        'start': start,
        'time': time,
        'timezone': timezone,
        if (scope != null) 'scope': scope,
        if (order != null) 'order': order,
        if (keepTogether != null) 'keepTogether': keepTogether,
        if (bookOrder != null) 'bookOrder': bookOrder,
        if (bookOrderMode != null) 'bookOrderMode': bookOrderMode,
      };

  Config copy() => Config.fromJson(toJson());
}

class TimeLog {
  int day;
  int seconds;
  String at;
  String? readingDate;
  TimeLog({required this.day, required this.seconds, required this.at, this.readingDate});
  factory TimeLog.fromJson(Map<String, Object?> j) => TimeLog(
      day: (j['day'] as num).toInt(),
      seconds: (j['seconds'] as num).toInt(),
      at: j['at'] as String,
      readingDate: j['readingDate'] as String?);
  Map<String, Object?> toJson() =>
      {'day': day, 'seconds': seconds, 'at': at, if (readingDate != null) 'readingDate': readingDate};
}

class PaceSample {
  int day;
  List<int> chapters;
  int seconds;
  String? review; // confirmed | excluded
  PaceSample({required this.day, required this.chapters, required this.seconds, this.review});
  factory PaceSample.fromJson(Map<String, Object?> j) => PaceSample(
      day: (j['day'] as num).toInt(),
      chapters: _ints(j['chapters']),
      seconds: (j['seconds'] as num).toInt(),
      review: j['review'] as String?);
  Map<String, Object?> toJson() =>
      {'day': day, 'chapters': chapters, 'seconds': seconds, if (review != null) 'review': review};
}

class PaceDraft {
  int day;
  List<int> before;
  int secondsBefore;
  bool? manual;
  PaceDraft({required this.day, required this.before, required this.secondsBefore, this.manual});
  factory PaceDraft.fromJson(Map<String, Object?> j) => PaceDraft(
      day: (j['day'] as num).toInt(),
      before: _ints(j['before']),
      secondsBefore: (j['secondsBefore'] as num).toInt(),
      manual: j['manual'] as bool?);
  Map<String, Object?> toJson() =>
      {'day': day, 'before': before, 'secondsBefore': secondsBefore, if (manual != null) 'manual': manual};
}

class PaceState {
  List<PaceSample> samples;
  PaceDraft? draft;
  PaceState({List<PaceSample>? samples, this.draft}) : samples = samples ?? [];
  factory PaceState.fromJson(Map<String, Object?> j) => PaceState(
      samples: [for (final s in j['samples'] as List) PaceSample.fromJson((s as Map).cast())],
      draft: j['draft'] == null ? null : PaceDraft.fromJson((j['draft'] as Map).cast()));
  Map<String, Object?> toJson() => {'samples': [for (final s in samples) s.toJson()], 'draft': draft?.toJson()};
}

class Session {
  String id;
  int day;
  String date;
  List<int> chapters;
  int seconds;
  Session({required this.id, required this.day, required this.date, required this.chapters, required this.seconds});
  factory Session.fromJson(Map<String, Object?> j) => Session(
      id: j['id'] as String,
      day: (j['day'] as num).toInt(),
      date: j['date'] as String,
      chapters: _ints(j['chapters']),
      seconds: (j['seconds'] as num).toInt());
  Map<String, Object?> toJson() => {'id': id, 'day': day, 'date': date, 'chapters': chapters, 'seconds': seconds};
}

class CorrectionSample {
  int day;
  List<String> references;
  int seconds;
  CorrectionSample(this.day, this.references, this.seconds);
  factory CorrectionSample.fromJson(Map<String, Object?> j) => CorrectionSample(
      (j['day'] as num).toInt(), [for (final r in j['references'] as List) r as String], (j['seconds'] as num).toInt());
  Map<String, Object?> toJson() => {'day': day, 'references': references, 'seconds': seconds};
}

class ChapterCorrection {
  // Original references, retained for review; never counted as new progress.
  List<String> previouslyRead;
  Map<String, String> done;
  List<CorrectionSample> samples;
  ChapterCorrection(this.previouslyRead, this.done, this.samples);
  factory ChapterCorrection.fromJson(Map<String, Object?> j) => ChapterCorrection(
      [for (final r in j['previouslyRead'] as List) r as String],
      (j['done'] as Map).map((k, v) => MapEntry(k as String, v as String)),
      [for (final s in j['samples'] as List) CorrectionSample.fromJson((s as Map).cast())]);
  Map<String, Object?> toJson() =>
      {'previouslyRead': previouslyRead, 'done': done, 'samples': [for (final s in samples) s.toJson()]};
}

class Adaptive {
  String date;
  List<List<int>> days;
  List<int> finished;
  IntKeyMap<List<int>> extra;
  List<int>? unplanned;
  Adaptive({required this.date, required this.days, required this.finished, IntKeyMap<List<int>>? extra, this.unplanned})
      : extra = extra ?? SplayTreeMap();
  factory Adaptive.fromJson(Map<String, Object?> j) => Adaptive(
      date: j['date'] as String,
      days: [for (final d in j['days'] as List) _ints(d)],
      finished: _ints(j['finished']),
      extra: _intMap(j['extra'], _ints),
      unplanned: j['unplanned'] == null ? null : _ints(j['unplanned']));
  Map<String, Object?> toJson() => {
        'date': date,
        if (unplanned != null) 'unplanned': unplanned,
        'days': days,
        'finished': finished,
        'extra': _strMap(extra, (v) => v),
      };
}

class TimerState {
  int day;
  int startedAt;
  TimerState(this.day, this.startedAt);
  factory TimerState.fromJson(Map<String, Object?> j) =>
      TimerState((j['day'] as num).toInt(), (j['startedAt'] as num).toInt());
  Map<String, Object?> toJson() => {'day': day, 'startedAt': startedAt};
}

class ReadingState {
  String id;
  int? chapterSchema;
  List<String>? editionReview;
  List<Session>? sessions;
  ChapterCorrection? chapterCorrection;
  Config config;
  Lang lang;
  // Apply a language-driven order change after the active timer pauses/ends.
  String? pendingBookOrder;
  IntKeyMap<String> done;
  List<int>? previouslyRead;
  // Keep completed units stable when a formerly expired plan is extended.
  IntKeyMap<int>? completionDays;
  List<TimeLog> logs;
  TimerState? timer;
  List<String> ops;
  PaceState? pace;
  Adaptive? adaptive;

  ReadingState({
    required this.id,
    this.chapterSchema,
    this.editionReview,
    this.sessions,
    this.chapterCorrection,
    required this.config,
    required this.lang,
    this.pendingBookOrder,
    IntKeyMap<String>? done,
    this.previouslyRead,
    this.completionDays,
    List<TimeLog>? logs,
    this.timer,
    List<String>? ops,
    this.pace,
    this.adaptive,
  })  : done = done ?? SplayTreeMap(),
        logs = logs ?? [],
        ops = ops ?? [];

  factory ReadingState.fromJson(Map<String, Object?> j) => ReadingState(
        id: j['id'] as String,
        chapterSchema: (j['chapterSchema'] as num?)?.toInt(),
        editionReview: (j['editionReview'] as List?)?.cast<String>().toList(),
        sessions: (j['sessions'] as List?)?.map((s) => Session.fromJson((s as Map).cast())).toList(),
        chapterCorrection: j['chapterCorrection'] == null
            ? null
            : ChapterCorrection.fromJson((j['chapterCorrection'] as Map).cast()),
        config: Config.fromJson((j['config'] as Map).cast()),
        lang: parseLang(j['lang']) ?? Lang.de,
        pendingBookOrder: j['pendingBookOrder'] as String?,
        done: _intMap(j['done'], (v) => v as String),
        previouslyRead: j['previouslyRead'] == null ? null : _ints(j['previouslyRead']),
        completionDays: j['completionDays'] == null ? null : _intMap(j['completionDays'], (v) => (v as num).toInt()),
        logs: [for (final l in j['logs'] as List) TimeLog.fromJson((l as Map).cast())],
        timer: j['timer'] == null ? null : TimerState.fromJson((j['timer'] as Map).cast()),
        ops: [for (final o in j['ops'] as List) o as String],
        pace: j['pace'] == null ? null : PaceState.fromJson((j['pace'] as Map).cast()),
        adaptive: j['adaptive'] == null ? null : Adaptive.fromJson((j['adaptive'] as Map).cast()),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (chapterSchema != null) 'chapterSchema': chapterSchema,
        if (editionReview != null) 'editionReview': editionReview,
        if (sessions != null) 'sessions': [for (final s in sessions!) s.toJson()],
        if (chapterCorrection != null) 'chapterCorrection': chapterCorrection!.toJson(),
        'config': config.toJson(),
        'lang': lang.name,
        if (pendingBookOrder != null) 'pendingBookOrder': pendingBookOrder,
        'done': _strMap(done, (v) => v),
        if (previouslyRead != null) 'previouslyRead': previouslyRead,
        if (completionDays != null) 'completionDays': _strMap(completionDays!, (v) => v),
        'logs': [for (final l in logs) l.toJson()],
        'timer': timer?.toJson(),
        'ops': ops,
        if (pace != null) 'pace': pace!.toJson(),
        if (adaptive != null) 'adaptive': adaptive!.toJson(),
      };

  /// Deep copy (structuredClone in the web app).
  ReadingState copy() => ReadingState.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, Object?>);
}

int daySeconds(ReadingState state, int day, [int? now]) {
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  return state.logs.where((l) => l.day == day).fold<int>(0, (s, l) => s + l.seconds) +
      (state.timer?.day == day ? max(0, ((n - state.timer!.startedAt) / 1000).floor()) : 0);
}
