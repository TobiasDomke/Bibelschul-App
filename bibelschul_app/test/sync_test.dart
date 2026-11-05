// Merging the versions of two devices never loses reading.
import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/adaptive.dart';
import 'package:bibelschul_app/core/notes.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/core/sync.dart';
import 'package:bibelschul_app/core/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final now = DateTime.now().millisecondsSinceEpoch;
  final start = today('Europe/Berlin', now);

  ReadingState plan() => applyAction(null, {
        'action': 'create',
        'config': {
          'amount': 60, 'unit': 'days', 'start': start, 'time': '07:30', 'timezone': 'Europe/Berlin',
          'scope': 'nt', 'order': 'canonical', 'keepTogether': true, 'bookOrderMode': 'auto',
        },
        'previouslyRead': <int>[], 'lang': 'de', 'planId': null, 'opId': uuid(),
      }, now);
  ReadingState act(ReadingState s, Map<String, Object?> op, [int? at]) =>
      applyAction(s, {...op, 'planId': s.id, 'opId': uuid()}, at ?? now);

  test('documents round-trip and are validated', () {
    final s = plan();
    final doc = SyncDocument(state: s, notes: const [], changedAt: now, previousSeconds: 3600);
    final back = SyncDocument.decode(doc.encode());
    expect(back.state!.id, s.id);
    expect(back.previousSeconds, 3600);
    expect(() => SyncDocument.decode('{"app":"other"}'), throwsA(isA<AppError>()));
    expect(() => SyncDocument.decode('nonsense'), throwsA(isA<AppError>()));
  });

  test('chapters read on two devices are both kept', () {
    final base = prepareState(plan(), start);
    final today = base.adaptive!.days[0];
    final a = act(base.copy(), {'action': 'chapter', 'chapter': today[0], 'done': true});
    final b = act(base.copy(), {'action': 'chapter', 'chapter': today[1], 'done': true}, now + 1000);
    final merged = mergeDocuments(
      SyncDocument(state: a, notes: const [], changedAt: now),
      SyncDocument(state: b, notes: const [], changedAt: now + 1000),
    );
    expect(merged.state!.done.keys, containsAll([today[0], today[1]]));
    expect(merged.changedAt, now + 1000);
    expect(isValidState(merged.state!), isTrue);
  });

  test('finished sessions and their times from both devices survive', () {
    final base = prepareState(plan(), start);
    final day = base.adaptive!.days[0];
    var a = act(base.copy(), {'action': 'timer', 'mode': 'start', 'day': 0});
    a = act(a, {'action': 'chapter', 'chapter': day[0], 'done': true}, now + 60000);
    a = act(a, {'action': 'complete', 'day': 0}, now + 300000);
    // The other device only checked a chapter of the same day, without timing.
    final b = act(base.copy(), {'action': 'chapter', 'chapter': day[1], 'done': true}, now + 400000);
    final merged = mergeDocuments(
      SyncDocument(state: a, notes: const [], changedAt: now + 300000),
      SyncDocument(state: b, notes: const [], changedAt: now + 400000),
    ).state!;
    expect(merged.done.keys, containsAll([day[0], day[1]]));
    expect(merged.logs.fold<int>(0, (s, l) => s + l.seconds), greaterThanOrEqualTo(300));
    expect(merged.adaptive!.finished, contains(0));
  });

  test('a new plan on one device replaces the old one; notes merge by id', () {
    final old = plan();
    final fresh = plan();
    final note = ReadingNote(id: 'n1', planId: old.id, day: 0, date: start, passage: 'x', text: 'a', updatedAt: 1);
    final newerNote = ReadingNote(id: 'n1', planId: old.id, day: 0, date: start, passage: 'x', text: 'b', updatedAt: 2);
    final merged = mergeDocuments(
      SyncDocument(state: old, notes: [newerNote], changedAt: now),
      SyncDocument(state: fresh, notes: [note], changedAt: now + 5),
    );
    expect(merged.state!.id, fresh.id);
    expect(merged.notes.single.text, 'b');
  });

  test('settings come from the device that changed last', () {
    final base = prepareState(plan(), start);
    final a = act(base.copy(), {'action': 'edition', 'edition': 'kjv'});
    final b = act(base.copy(), {'action': 'chapter', 'chapter': base.adaptive!.days[0][0], 'done': true});
    final merged = mergeDocuments(
      SyncDocument(state: a, notes: const [], changedAt: now + 10),
      SyncDocument(state: b, notes: const [], changedAt: now),
    ).state!;
    expect(merged.config.edition, 'kjv');
  });
}
