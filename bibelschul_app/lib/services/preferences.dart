import 'package:shared_preferences/shared_preferences.dart';

import '../core/languages.dart';

/// Device settings (language, appearance, backup history, reminders), like the
/// web app's localStorage. They are not part of the reading plan or backups.
class Preferences {
  Preferences(this._prefs);
  final SharedPreferences _prefs;

  static Future<Preferences> open() async => Preferences(await SharedPreferences.getInstance());

  /// The underlying store, for features that keep their own keys (reading groups).
  SharedPreferences get store => _prefs;

  Lang? get lang => parseLang(_prefs.getString('leseweg-lang'));
  set lang(Lang? value) => value == null ? _prefs.remove('leseweg-lang') : _prefs.setString('leseweg-lang', value.name);

  String? get theme => _prefs.getString('leseweg-theme');
  set theme(String? value) => value == null ? _prefs.remove('leseweg-theme') : _prefs.setString('leseweg-theme', value);

  bool get remindersEnabled => _prefs.getBool('leseweg-reminders') ?? false;
  set remindersEnabled(bool value) => _prefs.setBool('leseweg-reminders', value);

  bool get eveningReminder => _prefs.getBool('leseweg-evening') ?? false;
  set eveningReminder(bool value) => _prefs.setBool('leseweg-evening', value);

  String get eveningTime => _prefs.getString('leseweg-evening-time') ?? '20:00';
  set eveningTime(String value) => _prefs.setString('leseweg-evening-time', value);



  /// Date until which the "behind schedule" card stays hidden for a plan.
  String behindHiddenUntil(String planId) => _prefs.getString('leseweg-behind-$planId') ?? '';
  void hideBehind(String planId, String until) => _prefs.setString('leseweg-behind-$planId', until);

  /// Reading time the reader entered for chapters read before the plan.
  int? previousSeconds(String planId) => _prefs.getInt('leseweg-previous-seconds-$planId');
  Future<void> setPreviousSeconds(String planId, int? seconds) => seconds == null
      ? _prefs.remove('leseweg-previous-seconds-$planId')
      : _prefs.setInt('leseweg-previous-seconds-$planId', seconds);

  /// Optional name of a shared group plan.
  String groupName(String planId) => _prefs.getString('leseweg-group-$planId') ?? '';
  void setGroupName(String planId, String name) => name.isEmpty
      ? _prefs.remove('leseweg-group-$planId')
      : _prefs.setString('leseweg-group-$planId', name);
}
