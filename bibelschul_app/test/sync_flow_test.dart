// Two devices of one account: create, link with a code, read on both, sync.
import 'package:bibelschul_app/app/sync.dart';
import 'package:bibelschul_app/core/actions.dart';
import 'package:bibelschul_app/core/adaptive.dart';
import 'package:bibelschul_app/core/state.dart';
import 'package:bibelschul_app/core/sync.dart';
import 'package:bibelschul_app/core/util.dart';
import 'package:bibelschul_app/services/sync_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// The server in memory: one account, a revision and pairing codes.
class FakeServer {
  String? data;
  int revision = 0;
  final devices = <String, String>{}; // token -> device name
  final codes = <String>{};
}

class FakeSyncApi extends SyncApi {
  FakeSyncApi(super.token, this.server);
  final FakeServer server;
  SyncAccount get _account => SyncAccount('acc', 'Tobias', token.substring(0, 6), server.devices[token]!, server.devices.length);

  @override
  Future<(SyncAccount, String)> createAccount(String name, String deviceName) async {
    server.devices[token] = deviceName;
    return (_account, 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF');
  }

  @override
  Future<SyncSnapshot> fetch([int? since]) async {
    if (!server.devices.containsKey(token)) throw const SyncError('not_linked');
    return SyncSnapshot(_account, server.revision, since == server.revision ? null : server.data);
  }

  @override
  Future<int> upload(int baseRevision, String data) async {
    if (baseRevision != server.revision) throw SyncError('conflict', {'revision': server.revision, 'data': server.data});
    server.data = data;
    return ++server.revision;
  }

  @override
  Future<(String, int)> pair() async {
    server.codes.add('ABCD-EFGH');
    return ('ABCD-EFGH', 0);
  }

  @override
  Future<SyncAccount> join({String? code, String? recoveryCode, required String deviceName}) async {
    if (code != null && !server.codes.remove(code)) throw const SyncError('invalid_code');
    server.devices[token] = deviceName;
    return _account;
  }
}

/// A device: its own preferences and its own local document.
class Device {
  Device(this.prefs, FakeServer server, this.doc) {
    sync = SyncController(prefs, local: () async => doc.copyWith(changedAt: sync.changedAt), apply: (d) async => doc = d,
        api: (token) => FakeSyncApi(token, server));
  }
  final SharedPreferences prefs;
  SyncDocument doc;
  late final SyncController sync;

  void change(ReadingState state) {
    doc = doc.copyWith(state: state);
    sync.markChanged();
  }
}

extension on SyncDocument {
  SyncDocument copyWith({ReadingState? state, int? changedAt}) => SyncDocument(
      state: state ?? this.state, notes: notes, changedAt: changedAt ?? this.changedAt, previousSeconds: previousSeconds);
}

void main() {
  tzdata.initializeTimeZones();
  final now = DateTime.now().millisecondsSinceEpoch;
  final start = today('Europe/Berlin', now);

  test('a second device gets the plan and both readings meet', () async {
    final plan = prepareState(
        applyAction(null, {
          'action': 'create',
          'config': {
            'amount': 60, 'unit': 'days', 'start': start, 'time': '07:30', 'timezone': 'Europe/Berlin',
            'scope': 'nt', 'order': 'canonical', 'keepTogether': true, 'bookOrderMode': 'auto',
          },
          'previouslyRead': <int>[], 'lang': 'de', 'planId': null, 'opId': uuid(),
        }, now),
        start);
    final day = plan.adaptive!.days[0];
    final server = FakeServer();
    SharedPreferences.setMockInitialValues({});
    final iphone = Device(await SharedPreferences.getInstance(), server,
        SyncDocument(state: plan, notes: const [], changedAt: now));
    expect(await iphone.sync.createAccount('Tobias', 'iPhone'), isNotNull);
    expect(server.revision, 1);

    // The iPad has no plan yet and links with the code.
    SharedPreferences.setMockInitialValues({});
    final ipad = Device(await SharedPreferences.getInstance(), server, const SyncDocument(state: null, notes: [], changedAt: 0));
    final (code, _) = (await iphone.sync.pairingCode())!;
    expect(await ipad.sync.join(code: code, deviceName: 'iPad'), JoinResult.done);
    expect(ipad.doc.state!.id, plan.id);
    expect(ipad.sync.account!.name, 'Tobias');

    // Both read a different chapter while offline, then sync one after another.
    iphone.change(applyAction(iphone.doc.state!, {'action': 'chapter', 'chapter': day[0], 'done': true, 'planId': plan.id, 'opId': uuid()}, now));
    ipad.change(applyAction(ipad.doc.state!, {'action': 'chapter', 'chapter': day[1], 'done': true, 'planId': plan.id, 'opId': uuid()}, now));
    expect(await iphone.sync.syncNow(), isTrue);
    expect(await ipad.sync.syncNow(), isTrue);
    expect(await iphone.sync.syncNow(), isTrue);
    for (final device in [iphone, ipad]) {
      expect(device.doc.state!.done.keys, containsAll([day[0], day[1]]));
      expect(device.sync.dirty, isFalse);
    }
    // A used code does not work twice.
    SharedPreferences.setMockInitialValues({});
    final third = Device(await SharedPreferences.getInstance(), server, const SyncDocument(state: null, notes: [], changedAt: 0));
    expect(await third.sync.join(code: code, deviceName: 'Android'), isNull);
    expect(third.sync.error, 'invalid_code');
  });
}
