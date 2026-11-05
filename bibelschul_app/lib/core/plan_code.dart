import 'dart:convert';

import 'actions.dart';
import 'planner.dart';
import 'state.dart';

/// A shareable plan: only plan settings, never reading data. Reminder time and
/// time zone stay with each reader.
class SharedPlan {
  const SharedPlan(this.config, this.name);
  final Config config;
  final String name;
}

const _prefix = 'LESEWEG1.';

String encodePlanCode(Config config, String name) {
  final c = config.toJson()
    ..remove('time')
    ..remove('timezone');
  final payload = jsonEncode({'c': c, if (name.trim().isNotEmpty) 'n': name.trim()});
  return _prefix + base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
}

/// Returns null for anything that is not a valid plan code. Text around the
/// code (for example a chat message) is ignored.
SharedPlan? decodePlanCode(String raw, {required String time, required String timezone}) {
  final match = RegExp(r'LESEWEG1\.([A-Za-z0-9_-]+)').firstMatch(raw);
  if (match == null) return null;
  try {
    var data = match[1]!;
    data += '=' * ((4 - data.length % 4) % 4);
    final json = jsonDecode(utf8.decode(base64Url.decode(data)));
    if (json is! Map || json['c'] is! Map) return null;
    final name = json['n'];
    if (name != null && (name is! String || name.length > 80)) return null;
    final config = parseConfig({...(json['c'] as Map).cast<String, Object?>(), 'time': time, 'timezone': timezone});
    createPlan(isBible52(config) ? bible52Config(config) : config);
    return SharedPlan(config, (name as String?) ?? '');
  } catch (_) {
    return null;
  }
}
