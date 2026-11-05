// What the devices of one account exchange, and how two versions are merged.
//
// Each device keeps its full state locally and uploads it after changes. When
// two devices changed things independently (both offline, or at the same
// time), the versions are merged so that no reading is ever lost:
//   - chapters read, time measurements, sessions and pace samples of both are
//     combined (union, never removed by a merge),
//   - settings (plan, target, edition, chapters read before) come from the
//     version changed last,
//   - recommendations are rebuilt from the merged reading on the next load.
// Different plans (a new plan was created on one device) are not mixed: the
// more recently changed one wins.
import 'dart:convert';

import 'adaptive.dart';
import 'backup.dart';
import 'languages.dart';
import 'notes.dart';
import 'state.dart';
import 'util.dart';

class SyncDocument {
  const SyncDocument({
    required this.state,
    required this.notes,
    required this.changedAt,
    this.previousSeconds,
    this.groups,
  });

  /// null: no plan yet on that device.
  final ReadingState? state;
  final List<ReadingNote> notes;

  /// When the content last changed on any device (ms since epoch).
  final int changedAt;

  /// Entered time for the reading before [state]'s plan.
  final int? previousSeconds;

  /// Reading-group access, so all devices appear as one member.
  final GroupAccess? groups;

  String encode() => jsonEncode({
        'app': 'leseweg-sync',
        'version': 1,
        'changedAt': changedAt,
        'state': state?.toJson(),
        'notes': [for (final n in notes) n.toJson()],
        'previousSeconds': ?previousSeconds,
        if (groups != null) 'groups': {'token': groups!.token, 'name': groups!.name},
      });

  /// Validates like a backup; throws [AppError] for anything unusable.
  static SyncDocument decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      throw const AppError('sync');
    }
    if (json is! Map || json['app'] != 'leseweg-sync' || json['version'] != 1 || json['changedAt'] is! int) {
      throw const AppError('sync');
    }
    final stateJson = json['state'];
    ReadingState? state;
    if (stateJson != null) {
      if (stateJson is! Map) throw const AppError('sync');
      state = ReadingState.fromJson(stateJson.cast<String, Object?>());
      if (!isValidState(state)) throw const AppError('sync');
    }
    final notes = parseNotes(json['notes'] ?? const []);
    final previous = json['previousSeconds'];
    if (previous != null && (previous is! int || previous < 0 || previous > 36000000)) throw const AppError('sync');
    final groups = json['groups'];
    GroupAccess? access;
    if (groups != null) {
      if (groups is! Map ||
          groups['token'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(groups['token'] as String) ||
          groups['name'] is! String) {
        throw const AppError('sync');
      }
      access = (token: groups['token'] as String, name: groups['name'] as String);
    }
    return SyncDocument(
      state: state,
      notes: notes,
      changedAt: json['changedAt'] as int,
      previousSeconds: previous as int?,
      groups: access,
    );
  }
}

/// A state is usable when it passes the same checks as a backup.
bool isValidState(ReadingState state) {
  try {
    parseBackup(makeBackup(state, state.lang, 'light'));
    return true;
  } catch (_) {
    return false;
  }
}

/// Merges two versions of the same account.
SyncDocument mergeDocuments(SyncDocument local, SyncDocument remote) {
  final newer = remote.changedAt >= local.changedAt ? remote : local;
  final older = identical(newer, remote) ? local : remote;
  ReadingState? state;
  if (newer.state == null || older.state == null || newer.state!.id != older.state!.id) {
    state = newer.state ?? older.state;
  } else {
    state = mergeStates(newer.state!, older.state!, newer.changedAt);
  }
  final notes = <String, ReadingNote>{};
  for (final n in [...older.notes, ...newer.notes]) {
    final existing = notes[n.id];
    if (existing == null || n.updatedAt >= existing.updatedAt) notes[n.id] = n;
  }
  final samePlan = state != null && state.id == newer.state?.id;
  return SyncDocument(
    state: state,
    notes: notes.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
    changedAt: newer.changedAt,
    previousSeconds: samePlan ? (newer.previousSeconds ?? older.previousSeconds) : older.previousSeconds,
    groups: newer.groups ?? older.groups,
  );
}

/// Same plan on two devices: combine the reading, keep the newer settings.
ReadingState mergeStates(ReadingState newer, ReadingState older, int newerChangedAt) {
  final merged = newer.copy();
  final previous = {...?merged.previouslyRead};

  // Chapters read: union; the earlier date wins (that is when it was read).
  for (final MapEntry(key: id, value: date) in older.done.entries) {
    if (previous.contains(id)) continue;
    final current = merged.done[id];
    if (current == null || date.compareTo(current) < 0) merged.done[id] = date;
  }
  merged.done.removeWhere((id, _) => previous.contains(id));
  if (older.completionDays != null) {
    merged.completionDays ??= IntKeyMap();
    for (final MapEntry(key: id, value: day) in older.completionDays!.entries) {
      if (merged.done.containsKey(id)) merged.completionDays!.putIfAbsent(id, () => day);
    }
  }

  // Time measurements and sessions: union without duplicates.
  String logKey(TimeLog l) => '${l.day}|${l.at}|${l.seconds}';
  final logs = {for (final l in merged.logs) logKey(l)};
  for (final l in older.logs) {
    if (logs.add(logKey(l))) merged.logs.add(l);
  }
  merged.logs.sort((a, b) => a.at.compareTo(b.at));
  if (older.sessions != null) {
    final ids = {for (final s in merged.sessions ?? const <Session>[]) s.id};
    merged.sessions = [
      ...?merged.sessions,
      for (final s in older.sessions!)
        if (ids.add(s.id)) s,
    ]..sort((a, b) => a.date.compareTo(b.date));
  }
  if (older.pace != null) {
    String sampleKey(PaceSample s) => '${s.day}|${([...s.chapters]..sort()).join(',')}|${s.seconds}';
    merged.pace ??= PaceState(samples: [], draft: null);
    final keys = {for (final s in merged.pace!.samples) sampleKey(s)};
    for (final s in older.pace!.samples) {
      if (keys.add(sampleKey(s))) merged.pace!.samples.add(s);
    }
  }
  merged.ops = [
    ...{...older.ops, ...merged.ops}
  ].reversed.take(20).toList().reversed.toList();

  // A timer running only on the older version survives unless the newer
  // version changed after it started (then it was stopped there).
  final olderTimer = older.timer;
  if (merged.timer == null && olderTimer != null && olderTimer.startedAt > newerChangedAt) {
    merged.timer = olderTimer;
  }

  // Finished days of both count; recommendations are rebuilt on the next load.
  final finished = {...?merged.adaptive?.finished, ...?older.adaptive?.finished};
  if (merged.adaptive != null) {
    merged.adaptive!
      ..finished = (finished.toList()..sort())
      ..date = '1970-01-01';
  }
  try {
    final rebuilt = prepareState(merged, today(merged.config.timezone));
    if (isValidState(rebuilt)) return rebuilt;
  } catch (_) {}
  return newer;
}

/// For tests and the first link of a device: the language of a document.
Lang? documentLang(SyncDocument doc) => doc.state?.lang;
