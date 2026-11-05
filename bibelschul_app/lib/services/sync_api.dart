import 'dart:convert';
import 'dart:io';

import 'groups_api.dart' show groupsService;

/// The account as the server describes it to this device.
class SyncAccount {
  const SyncAccount(this.id, this.name, this.deviceId, this.deviceName, this.devices);
  final String id, name, deviceId, deviceName;
  final int devices;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'deviceId': deviceId, 'deviceName': deviceName, 'devices': devices};

  static SyncAccount fromJson(Map raw) => SyncAccount(
        raw['id'] as String,
        raw['name'] as String,
        raw['deviceId'] as String,
        raw['deviceName'] as String,
        (raw['devices'] as num?)?.toInt() ?? 1,
      );
}

class SyncDevice {
  const SyncDevice(this.id, this.name, this.lastSeen, this.me);
  final String id, name;
  final int lastSeen;
  final bool me;
}

/// Server answer of GET /sync: revision and, when it changed, the document.
class SyncSnapshot {
  const SyncSnapshot(this.account, this.revision, this.data);
  final SyncAccount account;
  final int revision;
  final String? data;
}

class SyncError implements Exception {
  const SyncError(this.code, [this.body = const {}]);
  final String code;
  final Map<String, Object?> body;
  @override
  String toString() => 'SyncError($code)';
}

/// JSON client for /sync (worker/sync.ts). The device token identifies this
/// installation; the server keeps only its hash.
class SyncApi {
  SyncApi(this.token, {this.base = groupsService});
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
      final response = await request.close().timeout(const Duration(seconds: 30));
      final text = await response.transform(utf8.decoder).join();
      Map<String, Object?> data;
      try {
        data = (jsonDecode(text) as Map).cast<String, Object?>();
      } catch (_) {
        throw const SyncError('unavailable');
      }
      if (response.statusCode >= 400) throw SyncError(data['error'] as String? ?? 'unavailable', data);
      return data;
    } on SyncError {
      rethrow;
    } catch (_) {
      throw const SyncError('offline');
    } finally {
      client.close(force: true);
    }
  }

  SyncAccount _account(Map<String, Object?> data) => SyncAccount.fromJson(data['account'] as Map);

  Future<(SyncAccount, String)> createAccount(String name, String deviceName) async {
    final data = await _call('POST', '/sync/account', {'name': name, 'deviceName': deviceName});
    return (_account(data), data['recoveryCode'] as String);
  }

  Future<SyncSnapshot> fetch([int? since]) async {
    final data = await _call('GET', since == null ? '/sync' : '/sync?since=$since');
    return SyncSnapshot(_account(data), (data['revision'] as num).toInt(), data['data'] as String?);
  }

  /// Returns the new revision; throws SyncError('conflict') with the server's
  /// current revision and data in [SyncError.body].
  Future<int> upload(int baseRevision, String data) async =>
      ((await _call('PUT', '/sync', {'baseRevision': baseRevision, 'data': data}))['revision'] as num).toInt();

  Future<(String, int)> pair() async {
    final data = await _call('POST', '/sync/pair');
    return (data['code'] as String, (data['expiresAt'] as num).toInt());
  }

  Future<SyncAccount> join({String? code, String? recoveryCode, required String deviceName}) async => _account(
      await _call('POST', '/sync/join', {'code': ?code, 'recoveryCode': ?recoveryCode, 'deviceName': deviceName}));

  Future<List<SyncDevice>> devices() async {
    final data = await _call('GET', '/sync/devices');
    return [
      for (final d in (data['devices'] as List? ?? const []))
        SyncDevice((d as Map)['id'] as String, d['name'] as String, (d['lastSeen'] as num?)?.toInt() ?? 0, d['me'] == true),
    ];
  }

  Future<void> removeDevice(String id) => _call('DELETE', '/sync/devices/$id');

  Future<String> newRecoveryCode() async => (await _call('POST', '/sync/recovery'))['recoveryCode'] as String;

  Future<SyncAccount> rename(String name) async => _account(await _call('PUT', '/sync/account', {'name': name}));

  Future<void> deleteAccount() => _call('DELETE', '/sync/account');
}

/// Pulls a pairing code out of typed text or a scanned link.
String? parsePairingCode(String raw) {
  const a = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final upper = raw.toUpperCase();
  final dashed = RegExp('(?<![A-Z0-9])([$a]{4})-([$a]{4})(?![A-Z0-9-])').firstMatch(upper);
  if (dashed != null) return '${dashed[1]}-${dashed[2]}';
  final compact = upper.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp('^[$a]{8}\$').hasMatch(compact)) return '${compact.substring(0, 4)}-${compact.substring(4)}';
  return null;
}

/// A recovery code: 24 characters, grouped by four.
String? parseRecoveryCode(String raw) {
  const a = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final compact = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp('^[$a]{24}\$').hasMatch(compact)) return null;
  return [for (var i = 0; i < 24; i += 4) compact.substring(i, i + 4)].join('-');
}

/// QR content for linking a device; the phone camera opens the Leseweg page.
String pairingLink(String code) => 'https://leseweg.pages.dev/#verbinden=$code';
