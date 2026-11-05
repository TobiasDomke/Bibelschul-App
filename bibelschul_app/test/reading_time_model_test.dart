// The reading-effort model: realistic totals, recent sessions count more and
// the app learns per kind of text how fast someone reads.
import 'package:bibelschul_app/core/difficulty.dart';
import 'package:bibelschul_app/core/pace.dart';
import 'package:bibelschul_app/core/planner.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingState _state(List<(List<int>, int)> samples) {
  final done = <String, String>{};
  for (final (ids, _) in samples) {
    for (final id in ids) {
      done['$id'] = '2026-11-01';
    }
  }
  return ReadingState.fromJson({
    'version': 9, 'id': 'x', 'lang': 'de', 'updatedAt': '2026-11-05T00:00:00Z',
    'config': {'amount': 12, 'unit': 'months', 'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin'},
    'done': done,
    'logs': [],
    'ops': [],
    'pace': {
      'samples': [
        for (final (i, (ids, seconds)) in samples.indexed) {'day': i, 'chapters': ids, 'seconds': seconds},
      ],
      'draft': null,
    },
  });
}

int _id(String code, int number) => chapters.firstWhere((c) => c.code == code && c.number == number).id;

void main() {
  test('text kinds', () {
    expect(textKind('GEN', 1), 'narrative');
    expect(textKind('GEN', 5), 'list');
    expect(textKind('1CH', 3), 'list');
    expect(textKind('EXO', 21), 'law');
    expect(textKind('PSA', 23), 'poetry');
    expect(textKind('ROM', 8), 'letter');
    expect(textKind('DAN', 3), 'narrative');
    expect(textKind('DAN', 9), 'apocalyptic');
    expect(textKind('JON', 2), 'narrative');
  });

  test('the whole Bible takes about 95 to 100 hours before any measurement', () {
    final pace = readingPace(null);
    final hours = chaptersSeconds(chapters, pace) / 3600;
    expect(hours, inInclusiveRange(95, 100));
    // A list chapter is quicker than a letter of the same length.
    final list = chapters[_id('1CH', 1)], letter = chapters[_id('ROM', 8)];
    expect(list.effort / list.words, lessThan(letter.effort / letter.words));
  });

  test('plans are balanced by reading time, not by words', () {
    final config = parseConfigForTest();
    final days = createPlan(config);
    final efforts = [for (final d in days) d.words];
    final mean = efforts.reduce((a, b) => a + b) / efforts.length;
    // Chapters are never split, so a single very long chapter may stand out;
    // all other days stay within 45 % of the average reading effort.
    expect(efforts.where((e) => (e - mean).abs() / mean >= 0.45).length, lessThanOrEqualTo(2));
  });

  test('recent sessions count more than old ones', () {
    final ids = [for (var n = 12; n <= 23; n++) _id('GEN', n)];
    double secondsAt(List<int> chapterIds, double secondsPerEffort) =>
        chapterIds.fold<int>(0, (s, id) => s + chapters[id].effort) * secondsPerEffort;
    // Six old slow sessions (0.8 s per unit), then six fast recent ones (0.4 s).
    final samples = [
      for (var i = 0; i < 6; i++) ([ids[i]], secondsAt([ids[i]], 0.8).round()),
      for (var i = 6; i < 12; i++) ([ids[i]], secondsAt([ids[i]], 0.4).round()),
    ];
    final pace = readingPace(_state(samples));
    expect(pace.personal, isTrue);
    expect(pace.secondsPerWord, lessThan(0.6), reason: 'closer to the recent 0.4 than the plain mean 0.6');
    expect(pace.secondsPerWord, greaterThan(0.4));
    expect(pace.wordsPerMinute, isNotNull);
  });

  test('slower psalms than stories are learned per kind of text', () {
    double secondsAt(int id, double secondsPerEffort) => chapters[id].effort * secondsPerEffort;
    final stories = [for (var n = 12; n <= 17; n++) _id('GEN', n)];
    final psalms = [for (var n = 1; n <= 6; n++) _id('PSA', n)];
    final samples = [
      for (final id in stories) ([id], secondsAt(id, 0.45).round()),
      for (final id in psalms) ([id], secondsAt(id, 0.9).round()),
    ];
    final pace = readingPace(_state(samples));
    expect(pace.kindFactors['poetry']!, greaterThan(1.2));
    expect(pace.kindFactors['narrative']!, lessThan(1));
    final psalm = chapters[_id('PSA', 23)], story = chapters[_id('GEN', 24)];
    expect(chaptersSeconds([psalm], pace) / psalm.effort, greaterThan(chaptersSeconds([story], pace) / story.effort));
  });
}

Config parseConfigForTest() => Config.fromJson({
      'amount': 12, 'unit': 'months', 'start': '2026-11-01', 'time': '07:30', 'timezone': 'Europe/Berlin',
      'scope': 'bible', 'order': 'canonical', 'keepTogether': true,
    });
