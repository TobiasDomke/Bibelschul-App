import 'dart:convert';
import 'dart:io';

/// Leseweg service (worker/index.ts + worker/groups.ts). Same address as the
/// web app's reminder service; reading groups live next to it.
const groupsService = 'https://leseweg-erinnerungen.tobidom01.workers.dev';

/// Numbers a member shares with a group – never notes or passages.
class MemberStats {
  const MemberStats({
    required this.chapters,
    required this.total,
    required this.weekChapters,
    required this.streak,
    required this.minutes,
    required this.wpm,
    required this.lastRead,
    required this.plan,
    this.progress,
  });
  final int chapters, total, weekChapters, streak, minutes;
  final int? wpm;
  final String? lastRead;
  final String plan;

  /// Share of the plan's text read, by words, in hundredths of a percent.
  /// Older app versions did not send it; then chapters are the fallback.
  final int? progress;

  double get percent => progress != null ? progress! / 100 : (total == 0 ? 0 : chapters / total * 100);

  Map<String, Object?> toJson() => {
        'chapters': chapters,
        'total': total,
        'weekChapters': weekChapters,
        'streak': streak,
        'minutes': minutes,
        'wpm': wpm,
        'lastRead': lastRead,
        'plan': plan,
        'progress': ?progress,
      };

  static MemberStats? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int n(String k) => (raw[k] as num?)?.toInt() ?? 0;
    return MemberStats(
      chapters: n('chapters'),
      total: n('total') == 0 ? 1 : n('total'),
      weekChapters: n('weekChapters'),
      streak: n('streak'),
      minutes: n('minutes'),
      wpm: (raw['wpm'] as num?)?.toInt(),
      lastRead: raw['lastRead'] as String?,
      plan: raw['plan'] as String? ?? '',
      progress: (raw['progress'] as num?)?.toInt(),
    );
  }
}

class GroupMember {
  const GroupMember(this.memberId, this.name, this.owner, this.me, this.stats, this.updatedAt);
  final String memberId, name;
  final bool owner, me;
  final MemberStats? stats;
  final int updatedAt;

  static GroupMember fromJson(Map raw) => GroupMember(
        raw['memberId'] as String,
        raw['name'] as String,
        raw['owner'] == true,
        raw['me'] == true,
        MemberStats.fromJson(raw['stats']),
        (raw['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class ReadingGroup {
  const ReadingGroup({
    required this.id,
    required this.name,
    required this.code,
    required this.owner,
    required this.visible,
    required this.hiddenCount,
    required this.members,
    required this.raw,
  });
  final String id, name, code;
  final bool owner, visible;
  final int hiddenCount;
  final List<GroupMember> members;

  /// Server answer, kept to show the last state offline.
  final Map<String, Object?> raw;

  int get memberCount => members.length + hiddenCount;

  static ReadingGroup fromJson(Map<String, Object?> raw) => ReadingGroup(
        id: raw['id'] as String,
        name: raw['name'] as String,
        code: raw['code'] as String,
        owner: raw['owner'] == true,
        visible: (raw['me'] as Map?)?['visible'] != false,
        hiddenCount: (raw['hiddenCount'] as num?)?.toInt() ?? 0,
        members: [for (final m in (raw['members'] as List? ?? const [])) GroupMember.fromJson(m as Map)],
        raw: raw,
      );
}

/// Error codes from the service, plus "offline" when it cannot be reached.
class GroupsError implements Exception {
  const GroupsError(this.code);
  final String code;
  @override
  String toString() => 'GroupsError($code)';
}

/// Thin JSON client. The token identifies this installation; only its hash is
/// stored on the server.
class GroupsApi {
  GroupsApi(this.token, {this.base = groupsService});
  final String token;
  final String base;

  Future<Map<String, Object?>> _call(String method, String path, [Map<String, Object?>? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse('$base$path')).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(const Duration(seconds: 15));
      final text = await response.transform(utf8.decoder).join();
      Map<String, Object?> data;
      try {
        data = (jsonDecode(text) as Map).cast<String, Object?>();
      } catch (_) {
        throw const GroupsError('unavailable');
      }
      if (response.statusCode >= 400) throw GroupsError(data['error'] as String? ?? 'unavailable');
      return data;
    } on GroupsError {
      rethrow;
    } catch (_) {
      throw const GroupsError('offline');
    } finally {
      client.close(force: true);
    }
  }

  ReadingGroup _group(Map<String, Object?> data) => ReadingGroup.fromJson((data['group'] as Map).cast<String, Object?>());

  Future<ReadingGroup> create(String groupName, String name, MemberStats? stats, bool visible) async =>
      _group(await _call('POST', '/groups',
          {'groupName': groupName, 'name': name, 'stats': stats?.toJson(), 'visible': visible}));

  Future<ReadingGroup> join(String code, String name, MemberStats? stats, bool visible) async =>
      _group(await _call('POST', '/groups/join', {'code': code, 'name': name, 'stats': stats?.toJson(), 'visible': visible}));

  Future<List<String>> list() async {
    final data = await _call('GET', '/groups');
    return [for (final g in (data['groups'] as List? ?? const [])) (g as Map)['id'] as String];
  }

  Future<ReadingGroup> get(String id) async => _group(await _call('GET', '/groups/$id'));

  Future<void> updateMe(String name, MemberStats? stats) =>
      _call('PUT', '/me', {'name': name, 'stats': stats?.toJson()});

  Future<ReadingGroup> setVisible(String id, bool visible) async =>
      _group(await _call('PUT', '/groups/$id/me', {'visible': visible}));

  Future<void> leave(String id) => _call('DELETE', '/groups/$id/me');

  Future<ReadingGroup> remove(String id, String memberId) async =>
      _group(await _call('DELETE', '/groups/$id/members/$memberId'));

  Future<ReadingGroup> newCode(String id) async => _group(await _call('POST', '/groups/$id/code'));

  Future<void> deleteAll() => _call('DELETE', '/me');
}

/// Pulls an invitation code out of typed text, a shared message or a link.
String? parseGroupCode(String raw) {
  const a = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final upper = raw.toUpperCase();
  final dashed = RegExp('(?<![A-Z0-9])([$a]{4})-([$a]{4})(?![A-Z0-9])').firstMatch(upper);
  if (dashed != null) return '${dashed[1]}-${dashed[2]}';
  final compact = upper.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp('^[$a]{8}\$').hasMatch(compact)) return '${compact.substring(0, 4)}-${compact.substring(4)}';
  return null;
}

/// Link inside invitations and QR codes. Scanned with the phone camera it opens
/// the Leseweg web page; inside the app the code is read from it.
String groupInviteLink(String code) => 'https://leseweg.pages.dev/#gruppe=$code';
