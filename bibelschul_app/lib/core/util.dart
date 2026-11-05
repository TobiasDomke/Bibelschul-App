import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

/// Error codes match the web app ("stale", "timer", "day", "finished", "invalid" ...).
class AppError implements Exception {
  final String code;
  const AppError(this.code);
  @override
  String toString() => 'AppError($code)';
}

/// JavaScript `Math.round`: halves round towards +infinity.
int jsRound(num value) => (value + 0.5).floor();

/// Calendar dates are ISO strings (YYYY-MM-DD) anchored at 12:00 UTC, as in the web app.
DateTime dateAt(String date) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (m == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).add(const Duration(days: -1000000));
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), 12);
}

bool isValidIsoDate(String date) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (m == null) return false;
  return isoDate(dateAt(date)) == date;
}

String isoDate(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

String addDays(String date, int days) => isoDate(dateAt(date).add(Duration(days: days)));

int daysBetween(String from, String to) =>
    jsRound(dateAt(to).difference(dateAt(from)).inMilliseconds / 86400000);

tz.Location location(String zone) => tz.getLocation(zone);

bool isValidTimezone(String zone) {
  if (zone == 'UTC') return true;
  try {
    tz.getLocation(zone);
    return true;
  } catch (_) {
    return false;
  }
}

tz.Location _loc(String zone) => zone == 'UTC' ? tz.UTC : tz.getLocation(zone);

/// Local calendar date in [zone] at [nowMs].
String today([String zone = 'Europe/Berlin', int? nowMs]) {
  final t = tz.TZDateTime.fromMillisecondsSinceEpoch(_loc(zone), nowMs ?? DateTime.now().millisecondsSinceEpoch);
  return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Local wall-clock parts of an instant, encoded as if it were UTC (like Intl formatToParts).
int localWallClockMs(int instantMs, String zone) {
  final t = tz.TZDateTime.fromMillisecondsSinceEpoch(_loc(zone), instantMs);
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second).millisecondsSinceEpoch;
}

/// Instant of [date] [time] in [zone]. A time skipped by DST moves forward by the gap.
DateTime zonedUTC(String date, String time, String zone) {
  final d = dateAt(date);
  final parts = time.split(':');
  final desired = DateTime.utc(d.year, d.month, d.day, int.parse(parts[0]), int.parse(parts[1])).millisecondsSinceEpoch;
  var candidate = desired;
  final seen = <int>[];
  for (var i = 0; i < 5; i++) {
    final local = localWallClockMs(candidate, zone);
    if (local == desired) return DateTime.fromMillisecondsSinceEpoch(candidate, isUtc: true);
    seen.add(candidate);
    candidate += desired - local;
    final at = seen.indexOf(candidate);
    if (at >= 0) {
      return DateTime.fromMillisecondsSinceEpoch(
          [candidate, ...seen.sublist(at)].reduce(max), isUtc: true);
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(candidate, isUtc: true);
}

final Random _random = Random.secure();

/// RFC 4122 version 4 UUID.
String uuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

final RegExp uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

String clockText(num seconds) {
  final s = max(0, seconds.floor());
  final h = s ~/ 3600;
  return '${h > 0 ? '$h:' : ''}${((s ~/ 60) % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// `{key}` placeholders, as in the web app's `fill`.
String fill(String value, Map<String, Object> params) =>
    value.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => '${params[m[1]] ?? '{${m[1]}}'}');
