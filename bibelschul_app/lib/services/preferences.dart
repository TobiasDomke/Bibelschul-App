import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/languages.dart';

/// Device settings (language, appearance, backup history, reminders), like the
/// web app's localStorage. They are not part of the reading plan or backups.
class Preferences {
  Preferences(this._prefs);
  final SharedPreferences _prefs;

  static Future<Preferences> open() async => Preferences(await SharedPreferences.getInstance());

  Lang? get lang => parseLang(_prefs.getString('leseweg-lang'));
  set lang(Lang? value) => value == null ? _prefs.remove('leseweg-lang') : _prefs.setString('leseweg-lang', value.name);

  String? get theme => _prefs.getString('leseweg-theme');
  set theme(String? value) => value == null ? _prefs.remove('leseweg-theme') : _prefs.setString('leseweg-theme', value);

  bool get remindersEnabled => _prefs.getBool('leseweg-reminders') ?? false;
  set remindersEnabled(bool value) => _prefs.setBool('leseweg-reminders', value);

  BackupStatus backupStatus(String? planId) {
    try {
      final raw = jsonDecode(_prefs.getString('leseweg-backup-${planId ?? ''}') ?? '{}') as Map;
      return BackupStatus(
        (raw['exported'] as num?)?.toInt() ?? 0,
        (raw['snoozed'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const BackupStatus(0, 0);
    }
  }

  Future<void> recordBackup(String planId, String kind) async {
    final current = backupStatus(planId);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(
      'leseweg-backup-$planId',
      jsonEncode({
        'exported': kind == 'exported' ? now : current.exported,
        'snoozed': kind == 'snoozed' ? now : current.snoozed,
      }),
    );
  }
}

class BackupStatus {
  final int exported;
  final int snoozed;
  const BackupStatus(this.exported, this.snoozed);
}
