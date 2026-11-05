import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/actions.dart';
import '../core/adaptive.dart';
import '../core/state.dart';
import '../core/util.dart';

/// Local reading data, stored only on this device (replaces the web app's IndexedDB).
///
/// Every change reads and writes inside one serialized section, like the web
/// app's single IndexedDB transaction. Writes go to a temporary file first and
/// are then renamed, so an interrupted write never leaves a half-written plan.
/// Before risky migrations an unchanged copy is kept next to the plan.
class ReadingStore {
  ReadingStore(this.directory);

  final Directory directory;
  Future<void> _queue = Future.value();

  static Future<ReadingStore> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/leseweg');
    await dir.create(recursive: true);
    return ReadingStore(dir);
  }

  File _file(String key) => File('${directory.path}/$key.json');

  Future<ReadingState?> _get(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    return ReadingState.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
  }

  Future<void> _put(String key, ReadingState state) async {
    final file = _file(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<ReadingState?> _transaction(ReadingState? Function(ReadingState? state)? update) {
    final completer = Completer<ReadingState?>();
    _queue = _queue.then((_) async {
      try {
        var result = await _get('active');
        if (update != null) {
          if (result != null && result.chapterSchema != 2) await _put('before-chapter-schema-2', result);
          if (result != null && result.sessions == null) await _put('before-editions-and-sessions', result);
          final original = result;
          result = update(result);
          if (original != null &&
              result != null &&
              original.id == result.id &&
              original.config.edition != result.config.edition) {
            await _put('before-edition-${original.config.edition ?? 'schlachter2000'}', original);
          }
          if (result != null) await _put('active', result);
        }
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Upgrade inside the same serialized section as other plan changes.
  Future<ReadingState?> read() =>
      _transaction((state) => state != null && state.chapterSchema != 2 ? prepareState(state) : state);

  Future<ReadingState> change(Map<String, Object?> op) async =>
      (await _transaction((state) => applyAction(state, op)))!;

  Future<ReadingState> restore(ReadingState state, String? expectedId) async =>
      (await _transaction((current) {
        if (current?.id != expectedId) throw const AppError('stale');
        return state.copy()
          ..id = uuid()
          ..ops = [];
      }))!;
}
