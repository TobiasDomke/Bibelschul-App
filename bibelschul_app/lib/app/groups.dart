import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/groups_api.dart';
import 'plan_view.dart';
import 'reading_stats.dart';

/// Reading groups: membership, the shared numbers and a local copy of the last
/// answer so the list also shows something offline. Nothing is sent until the
/// reader creates or joins a group.
class GroupsController extends ChangeNotifier {
  GroupsController(this._prefs, {GroupsApi Function(String token)? api})
      : _api = api ?? ((token) => GroupsApi(token));

  final SharedPreferences _prefs;
  final GroupsApi Function(String token) _api;

  static const _tokenKey = 'leseweg-groups-token';
  static const _nameKey = 'leseweg-groups-name';
  static const _cacheKey = 'leseweg-groups-cache';
  static const _syncedKey = 'leseweg-groups-synced';

  bool loading = false;

  /// Last error code ("offline", "group_not_found" …) or "".
  String error = '';

  String get name => _prefs.getString(_nameKey) ?? '';
  int get syncedAt => _prefs.getInt(_syncedKey) ?? 0;

  List<ReadingGroup> get groups {
    try {
      final raw = jsonDecode(_prefs.getString(_cacheKey) ?? '[]') as List;
      return [for (final g in raw) ReadingGroup.fromJson((g as Map).cast<String, Object?>())];
    } catch (_) {
      return const [];
    }
  }

  bool get joined => groups.isNotEmpty;

  String get _token {
    var token = _prefs.getString(_tokenKey);
    if (token == null || token.length != 43) {
      final random = Random.secure();
      token = base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]).replaceAll('=', '');
      _prefs.setString(_tokenKey, token);
    }
    return token;
  }

  GroupsApi get _client => _api(_token);

  Future<void> _store(List<ReadingGroup> list) async {
    await _prefs.setString(_cacheKey, jsonEncode([for (final g in list) g.raw]));
    await _prefs.setInt(_syncedKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _replace(ReadingGroup group) async {
    final list = [...groups];
    final i = list.indexWhere((g) => g.id == group.id);
    if (i >= 0) {
      list[i] = group;
    } else {
      list.add(group);
    }
    await _store(list);
  }

  /// Runs [work], keeps [error] and returns whether it worked.
  Future<bool> _run(Future<void> Function() work) async {
    loading = true;
    error = '';
    notifyListeners();
    try {
      await work();
      return true;
    } on GroupsError catch (e) {
      error = e.code;
      return false;
    } catch (_) {
      error = 'unavailable';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// The numbers shared with groups, derived from the current plan.
  static MemberStats? statsOf(PlanView? v) {
    if (v == null) return null;
    final s = v.state;
    final label = v.fixed ? 'Bibelleseplan 52' : v.planLabel;
    return MemberStats(
      chapters: min(v.doneCount, v.scoped.length).clamp(0, 2000),
      total: v.scoped.length.clamp(1, 2000),
      weekChapters: chaptersThisWeek(s, v.currentDate).clamp(0, 2000),
      streak: readingStreak(s, v.currentDate).clamp(0, 10000),
      minutes: (v.totalSeconds ~/ 60).clamp(0, 1000000),
      wpm: wordsPerMinute(v.pace),
      lastRead: lastReadDate(s),
      plan: label.length > 60 ? label.substring(0, 60) : label,
    );
  }

  Future<bool> setName(String value, PlanView? v) async {
    await _prefs.setString(_nameKey, value.trim());
    notifyListeners();
    if (!joined) return true;
    return _run(() => _client.updateMe(value.trim(), statsOf(v)));
  }

  Future<bool> create(String groupName, String member, PlanView? v) async {
    await _prefs.setString(_nameKey, member.trim());
    return _run(() async => _replace(await _client.create(groupName.trim(), member.trim(), statsOf(v), true)));
  }

  Future<bool> join(String code, String member, PlanView? v) async {
    await _prefs.setString(_nameKey, member.trim());
    return _run(() async => _replace(await _client.join(code, member.trim(), statsOf(v), true)));
  }

  /// Sends the current numbers, then reloads every group.
  Future<bool> refresh(PlanView? v) async {
    if (!joined) return true;
    return _run(() async {
      final client = _client;
      await client.updateMe(name, statsOf(v));
      final ids = await client.list();
      final order = [for (final g in groups) g.id];
      ids.sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
      });
      await _store([for (final id in ids) await client.get(id)]);
    });
  }

  /// After a finished reading unit: share the new numbers quietly.
  Future<void> pushStats(PlanView? v) async {
    if (!joined || name.isEmpty) return;
    try {
      await _client.updateMe(name, statsOf(v));
    } catch (_) {
      // Groups must never disturb reading; the next refresh catches up.
    }
  }

  Future<bool> setVisible(ReadingGroup group, bool visible) =>
      _run(() async => _replace(await _client.setVisible(group.id, visible)));

  Future<bool> leave(ReadingGroup group) => _run(() async {
        try {
          await _client.leave(group.id);
        } on GroupsError catch (e) {
          if (e.code != 'group_not_found') rethrow;
        }
        await _store([for (final g in groups) if (g.id != group.id) g]);
      });

  Future<bool> remove(ReadingGroup group, GroupMember member) =>
      _run(() async => _replace(await _client.remove(group.id, member.memberId)));

  Future<bool> newCode(ReadingGroup group) => _run(() async => _replace(await _client.newCode(group.id)));

  /// What a backup needs to bring the memberships back after a reinstall.
  ({String token, String name})? get access => joined ? (token: _token, name: name) : null;

  /// Takes over the group access of a restored backup and loads its groups.
  Future<bool> restoreAccess(({String token, String name}) access, PlanView? v) async {
    if (access.token == _prefs.getString(_tokenKey) && joined) return refresh(v);
    await _prefs.setString(_tokenKey, access.token);
    await _prefs.setString(_nameKey, access.name);
    await _store(const []);
    return _run(() async {
      final client = _client;
      final ids = await client.list();
      await _store([for (final id in ids) await client.get(id)]);
      if (ids.isNotEmpty && access.name.isNotEmpty) await client.updateMe(access.name, statsOf(v));
    });
  }

  /// Leaves every group and deletes the shared numbers on the server.
  Future<bool> deleteAll() => _run(() async {
        await _client.deleteAll();
        await _store(const []);
      });
}
