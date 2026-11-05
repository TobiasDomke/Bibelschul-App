import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/sync.dart';
import '../services/sync_api.dart';

/// What happened when a device joined an account that already has a plan
/// different from the one on this device.
enum JoinResult { done, choosePlan }

/// Keeps this device in step with the other devices of the account.
///
/// Every local change marks the device "dirty" and schedules an upload a few
/// seconds later; opening the app pulls changes. If both sides changed, the
/// versions are merged (core/sync.dart) – reading is never lost.
class SyncController extends ChangeNotifier {
  SyncController(
    this._prefs, {
    required this.local,
    required this.apply,
    SyncApi Function(String token)? api,
  }) : _api = api ?? ((token) => SyncApi(token));

  final SharedPreferences _prefs;
  final SyncApi Function(String token) _api;

  /// The current local document.
  final Future<SyncDocument> Function() local;

  /// Stores a merged/remote document on this device.
  final Future<void> Function(SyncDocument doc) apply;

  static const _tokenKey = 'leseweg-sync-token';
  static const _accountKey = 'leseweg-sync-account';
  static const _revisionKey = 'leseweg-sync-revision';
  static const _dirtyKey = 'leseweg-sync-dirty';
  static const _changedKey = 'leseweg-sync-changed-at';
  static const _syncedKey = 'leseweg-sync-at';

  bool running = false;

  /// Last error code ("offline", "not_linked" …) or "".
  String error = '';
  Timer? _debounce;

  /// A remote plan waiting for the reader's choice after joining.
  SyncDocument? pendingRemote;
  int? _pendingRevision;

  SyncAccount? get account {
    final raw = _prefs.getString(_accountKey);
    if (raw == null) return null;
    try {
      return SyncAccount.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  bool get linked => account != null;
  int get syncedAt => _prefs.getInt(_syncedKey) ?? 0;
  int get changedAt => _prefs.getInt(_changedKey) ?? 0;
  bool get dirty => _prefs.getBool(_dirtyKey) ?? false;
  int get _revision => _prefs.getInt(_revisionKey) ?? 0;

  String get _token {
    var token = _prefs.getString(_tokenKey);
    if (token == null || token.length != 43) {
      final random = Random.secure();
      token = base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]).replaceAll('=', '');
      _prefs.setString(_tokenKey, token);
    }
    return token;
  }

  SyncApi get _client => _api(_token);

  Future<void> _saveAccount(SyncAccount a) => _prefs.setString(_accountKey, jsonEncode(a.toJson()));

  /// Call after every local change of plan, reading or notes.
  void markChanged() {
    _prefs.setInt(_changedKey, DateTime.now().millisecondsSinceEpoch);
    _prefs.setBool(_dirtyKey, true);
    if (!linked) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
  }

  Future<T?> _run<T>(Future<T> Function() work) async {
    running = true;
    error = '';
    notifyListeners();
    try {
      return await work();
    } on SyncError catch (e) {
      error = e.code;
      if (e.code == 'not_linked' || e.code == 'unauthorized') await _forget();
      return null;
    } catch (_) {
      error = 'unavailable';
      return null;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// Pull, merge if needed, push. Safe to call any time.
  Future<bool> syncNow() async {
    if (!linked || running) return false;
    final ok = await _run(() async {
      await _syncOnce();
      return true;
    });
    return ok ?? false;
  }

  Future<void> _syncOnce() async {
    final client = _client;
    for (var attempt = 0; attempt < 3; attempt++) {
      final snapshot = await client.fetch(_revision < 0 ? null : _revision);
      await _saveAccount(snapshot.account);
      var revision = snapshot.revision;
      final mine = await local();
      SyncDocument outgoing = mine;
      if (snapshot.data != null) {
        final remote = SyncDocument.decode(snapshot.data!);
        final merged = dirty ? mergeDocuments(mine, remote) : remote;
        await apply(merged);
        outgoing = merged;
        if (!dirty && merged.encode() == remote.encode()) {
          await _done(revision);
          return;
        }
      } else if (!dirty) {
        await _done(revision);
        return;
      }
      try {
        revision = await client.upload(revision, outgoing.encode());
        await _done(revision);
        return;
      } on SyncError catch (e) {
        if (e.code != 'conflict') rethrow;
        // Someone else uploaded in between: merge with theirs next round.
        await _prefs.setInt(_revisionKey, -1);
      }
    }
    throw const SyncError('conflict');
  }

  Future<void> _done(int revision) async {
    await _prefs.setInt(_revisionKey, revision);
    await _prefs.setBool(_dirtyKey, false);
    await _prefs.setInt(_syncedKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// First device: creates the account and uploads this device's data.
  /// Returns the recovery code to show once.
  Future<String?> createAccount(String name, String deviceName) => _run(() async {
        final (account, recovery) = await _client.createAccount(name.trim(), deviceName.trim());
        await _saveAccount(account);
        await _prefs.setInt(_revisionKey, 0);
        await _prefs.setBool(_dirtyKey, true);
        await _syncOnce();
        return recovery;
      });

  /// Further device: joins with a pairing code or the recovery code.
  Future<JoinResult?> join({String? code, String? recoveryCode, required String deviceName}) => _run(() async {
        final client = _client;
        final account = await client.join(code: code, recoveryCode: recoveryCode, deviceName: deviceName.trim());
        await _saveAccount(account);
        await _prefs.setInt(_revisionKey, -1);
        final snapshot = await client.fetch();
        final mine = await local();
        final remote = snapshot.data == null ? null : SyncDocument.decode(snapshot.data!);
        if (remote?.state != null && mine.state != null && remote!.state!.id != mine.state!.id) {
          pendingRemote = remote;
          _pendingRevision = snapshot.revision;
          return JoinResult.choosePlan;
        }
        await _prefs.setBool(_dirtyKey, mine.state != null);
        await _syncOnce();
        return JoinResult.done;
      });

  /// After [JoinResult.choosePlan]: keep the account's plan or this device's.
  Future<bool> choosePlan({required bool keepAccount}) async {
    final remote = pendingRemote;
    if (remote == null) return false;
    final ok = await _run(() async {
      if (keepAccount) {
        await apply(remote);
        await _done(_pendingRevision ?? 0);
      } else {
        await _prefs.setInt(_changedKey, DateTime.now().millisecondsSinceEpoch);
        final mine = await local();
        await _done(await _client.upload(_pendingRevision ?? 0, mine.encode()));
      }
      return true;
    });
    pendingRemote = null;
    return ok ?? false;
  }

  Future<(String, int)?> pairingCode() => _run(() => _client.pair());

  Future<List<SyncDevice>?> devices() async {
    try {
      return await _client.devices();
    } catch (_) {
      return null;
    }
  }

  Future<bool> removeDevice(SyncDevice device) async {
    final ok = await _run(() async {
      await _client.removeDevice(device.id);
      if (device.me) await _forget();
      return true;
    });
    return ok ?? false;
  }

  Future<String?> newRecoveryCode() => _run(() => _client.newRecoveryCode());

  Future<bool> rename(String name) async {
    final ok = await _run(() async {
      await _saveAccount(await _client.rename(name.trim()));
      return true;
    });
    return ok ?? false;
  }

  /// Signs this device out; its data stays on the device.
  Future<bool> signOut() async {
    final me = account;
    if (me == null) return true;
    return removeDevice(SyncDevice(me.deviceId, me.deviceName, 0, true));
  }

  /// Deletes the account and everything stored for it on the server.
  Future<bool> deleteAccount() async {
    final ok = await _run(() async {
      await _client.deleteAccount();
      await _forget();
      return true;
    });
    return ok ?? false;
  }

  Future<void> _forget() async {
    _debounce?.cancel();
    await _prefs.remove(_accountKey);
    await _prefs.remove(_revisionKey);
    await _prefs.remove(_tokenKey); // a fresh identity for a later link
    pendingRemote = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
