import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/languages.dart';
import '../core/notes.dart';
import '../core/state.dart';
import '../core/util.dart';

/// Keeps the last [keep] daily backup files in the app's Documents folder.
///
/// On iOS this folder is visible in the Files app ("On My iPhone › Leseweg")
/// because Info.plist enables file sharing; on both platforms it is part of
/// the system device backup (iCloud / Google). One file per day is enough:
/// later sessions on the same day overwrite it.
class AutoBackup {
  AutoBackup(this.directory);
  final Directory directory;
  static const keep = 10;

  static Future<AutoBackup> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Sicherungen');
    return AutoBackup(dir);
  }

  Future<File> write(ReadingState state, Lang lang, String theme, List<ReadingNote> notes, [int? nowMs]) async {
    await directory.create(recursive: true);
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/leseweg-sicherung-${today(state.config.timezone, now)}.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(makeAppBackup(state, lang, theme, notes, now), flush: true);
    await temp.rename(file.path);
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'leseweg-sicherung-\d{4}-\d{2}-\d{2}\.json$').hasMatch(f.path))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(keep)) {
      await old.delete();
    }
    return file;
  }
}
