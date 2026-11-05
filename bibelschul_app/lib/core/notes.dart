import 'dart:convert';

import 'backup.dart';
import 'languages.dart';
import 'state.dart';
import 'util.dart';

/// A personal thought about one reading unit (app-only feature).
///
/// Notes are stored next to the reading plan, not inside it, so the plan
/// format stays identical to the web app. [planId] and [day] link a note to
/// the unit it was written for; [passage] keeps a readable reference even if
/// the plan is later replaced.
class ReadingNote {
  ReadingNote({
    required this.id,
    required this.planId,
    required this.day,
    required this.date,
    required this.passage,
    required this.text,
    required this.updatedAt,
  });

  final String id;
  String planId;
  final int day;
  final String date;
  String passage;
  String text;
  int updatedAt;

  factory ReadingNote.fromJson(Map<String, Object?> j) => ReadingNote(
        id: j['id'] as String,
        planId: j['planId'] as String,
        day: (j['day'] as num).toInt(),
        date: j['date'] as String,
        passage: j['passage'] as String,
        text: j['text'] as String,
        updatedAt: (j['updatedAt'] as num).toInt(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'planId': planId,
        'day': day,
        'date': date,
        'passage': passage,
        'text': text,
        'updatedAt': updatedAt,
      };
}

const maxNoteLength = 10000;

/// Strict validation of imported notes.
List<ReadingNote> parseNotes(Object? raw) {
  if (raw is! List || raw.length > 5000) throw const AppError('backup');
  final ids = <String>{};
  return [
    for (final item in raw)
      () {
        if (item is! Map) throw const AppError('backup');
        final m = item.cast<String, Object?>();
        const keys = ['id', 'planId', 'day', 'date', 'passage', 'text', 'updatedAt'];
        if (m.keys.any((k) => !keys.contains(k)) ||
            m['id'] is! String ||
            (m['id'] as String).length > 100 ||
            !ids.add(m['id'] as String) ||
            m['planId'] is! String ||
            (m['planId'] as String).length > 100 ||
            m['day'] is! num ||
            (m['day'] as num) < 0 ||
            (m['day'] as num) > 3649 ||
            m['date'] is! String ||
            !isValidIsoDate(m['date'] as String) ||
            m['passage'] is! String ||
            (m['passage'] as String).length > 500 ||
            m['text'] is! String ||
            (m['text'] as String).length > maxNoteLength ||
            m['updatedAt'] is! num) {
          throw const AppError('backup');
        }
        return ReadingNote.fromJson(m);
      }(),
  ];
}

/// Access to reading groups, so a restored installation keeps its memberships.
typedef GroupAccess = ({String token, String name});

class AppBackup {
  const AppBackup(this.backup, this.notes, [this.groups]);
  final Backup backup;
  final List<ReadingNote> notes;
  final GroupAccess? groups;
}

/// Version 8 (web-compatible) without notes or groups; version 9 adds a
/// `notes` list and, for members of reading groups, a `groups` entry.
String makeAppBackup(ReadingState state, Lang lang, String theme, List<ReadingNote> notes,
    [int? nowMs, GroupAccess? groups]) {
  final json = makeBackup(state, lang, theme, nowMs);
  if (notes.isEmpty && groups == null) return json;
  final data = jsonDecode(json) as Map<String, Object?>;
  return const JsonEncoder.withIndent('  ').convert({
    ...data,
    'version': 9,
    'notes': [for (final n in notes) n.toJson()],
    if (groups != null) 'groups': {'token': groups.token, 'name': groups.name},
  });
}

GroupAccess? _parseGroups(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map ||
      raw['token'] is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(raw['token'] as String) ||
      raw['name'] is! String ||
      (raw['name'] as String).length > 40) {
    throw const AppError('backup');
  }
  return (token: raw['token'] as String, name: raw['name'] as String);
}

/// Reads web backups (versions 1–8) and app backups with notes (version 9).
AppBackup parseAppBackup(String raw) {
  if (raw.length > maxBackupBytes) throw const AppError('backup');
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    throw const AppError('backup');
  }
  if (json is Map && json['version'] == 9) {
    final data = Map<String, Object?>.from(json.cast<String, Object?>());
    final notes = parseNotes(data.remove('notes'));
    final groups = _parseGroups(data.remove('groups'));
    data['version'] = 8;
    return AppBackup(parseBackup(jsonEncode(data)), notes, groups);
  }
  return AppBackup(parseBackup(raw), const []);
}

/// Restored plans get a new id; notes of that plan follow it. Existing notes are kept.
List<ReadingNote> mergeRestoredNotes(
    List<ReadingNote> current, List<ReadingNote> restored, String oldPlanId, String newPlanId) {
  final byId = {for (final n in current) n.id: n};
  for (final n in restored) {
    if (n.planId == oldPlanId) n.planId = newPlanId;
    byId[n.id] = n;
  }
  return byId.values.toList()..sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.updatedAt - a.updatedAt);
}

/// Plain-text export of all notes, newest first.
String notesText(List<ReadingNote> notes, String title) {
  final buffer = StringBuffer('$title\n\n');
  for (final n in notes) {
    buffer
      ..writeln('${n.date} · ${n.passage}')
      ..writeln(n.text.trim())
      ..writeln();
  }
  return buffer.toString();
}
