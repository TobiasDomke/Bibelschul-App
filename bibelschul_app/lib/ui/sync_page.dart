import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../app/sync.dart';
import '../core/languages.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import '../services/files.dart';
import '../services/sync_api.dart';
import 'dialogs.dart';
import 'settings_tab.dart' show ScanPage;
import 'theme.dart';
import 'widgets.dart';

/// "iPhone", "iPad" or "Android" as a starting name for this device.
String defaultDeviceName(BuildContext context) {
  if (Platform.isAndroid) return 'Android';
  return MediaQuery.sizeOf(context).shortestSide >= 600 ? 'iPad' : 'iPhone';
}

String syncErrorText(Lang lang, String code) {
  final u = ui(lang);
  return switch (code) {
    'offline' => u['syncOffline'],
    'invalid_code' => u['syncCodeInvalid'],
    'too_many_devices' => u['syncTooMany'],
    'already_linked' => u['syncAlreadyLinked'],
    'invalid_name' || 'invalid_device_name' => u['nameInvalid'],
    'rate_limited' => u['rateLimited'],
    _ => u['syncDown'],
  };
}

/// Account and devices: create the account, link devices, see who is signed in.
class SyncCard extends StatelessWidget {
  const SyncCard({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: c.sync, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final lang = c.lang;
    final u = ui(lang), t = text(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final s = c.sync;
    final account = s.account;

    if (account == null) {
      return Panel(
        child: Gap(space: 12, children: [
          Icon(Icons.cloud_sync_outlined, color: palette.primary, size: 28),
          Heading(u['syncIntroTitle'], size: 20),
          Text(u['syncIntro']),
          Notice(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline, size: 18, color: palette.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(u['syncPrivacy'])),
            ]),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: s.running ? null : () => createAccount(context, c),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: Text(u['syncCreate']),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: s.running ? null : () => linkDevice(context, c),
              icon: const Icon(Icons.link, size: 18),
              label: Text(u['syncLink']),
            ),
          ),
          if (s.running) const LinearProgressIndicator(),
          if (s.error.isNotEmpty) Notice(text: syncErrorText(lang, s.error), kind: NoticeKind.error),
        ]),
      );
    }

    final status = s.running
        ? u['syncRunning']
        : (s.error.isNotEmpty
            ? syncErrorText(lang, s.error)
            : (s.syncedAt > 0 ? fill(u['syncDone'], {'time': fmt.dateTime(s.syncedAt)}) : u['syncNever']));
    return Gap(space: 14, children: [
      Panel(
        child: Gap(space: 12, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              child: Text(account.name.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Muted(u['syncSignedInAs'], size: 13),
                Text(account.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: palette.foreground)),
                Muted(fill(u['syncThisDevice'], {'device': account.deviceName}), size: 13),
              ]),
            ),
          ]),
          Row(children: [
            Icon(s.error.isNotEmpty ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                size: 18, color: s.error.isNotEmpty ? palette.mutedForeground : palette.primary),
            const SizedBox(width: 8),
            Expanded(child: Muted(status, size: 13)),
            TextButton(onPressed: s.running ? null : s.syncNow, child: Text(u['syncNow'])),
          ]),
          if (s.running) const LinearProgressIndicator(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: s.running ? null : () => showPairing(context, c),
              icon: const Icon(Icons.add_to_home_screen, size: 18),
              label: Text(u['syncAddDevice']),
            ),
          ),
          FinePrint(u['syncHow']),
        ]),
      ),
      _Devices(c: c),
      Panel(
        child: Gap(space: 10, children: [
          Heading(u['syncRecoveryTitle'], size: 17),
          Muted(u['syncRecoveryHelp'], size: 13.5),
          OutlinedButton.icon(
            onPressed: s.running
                ? null
                : () async {
                    if (!await confirmDialog(context,
                        title: u['syncRecoveryNew'], body: u['syncRecoveryNewText'], confirm: u['syncRecoveryNew'], cancel: t.cancel)) {
                      return;
                    }
                    final code = await s.newRecoveryCode();
                    if (code != null && context.mounted) await showRecoveryCode(context, c, code);
                  },
            icon: const Icon(Icons.key_outlined, size: 18),
            label: Text(u['syncRecoveryNew']),
          ),
        ]),
      ),
      Panel(
        child: Gap(space: 4, children: [
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: s.running
                ? null
                : () async {
                    if (await confirmDialog(context,
                        title: u['syncSignOut'], body: u['syncSignOutText'], confirm: u['syncSignOut'], cancel: t.cancel)) {
                      await s.signOut();
                    }
                  },
            icon: const Icon(Icons.logout, size: 18),
            label: Text(u['syncSignOut']),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: palette.destructive),
            onPressed: s.running
                ? null
                : () async {
                    if (await confirmDialog(context,
                        title: u['syncDelete'], body: u['syncDeleteText'], confirm: u['syncDelete'], cancel: t.cancel)) {
                      await s.deleteAccount();
                    }
                  },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(u['syncDelete']),
          ),
        ]),
      ),
    ]);
  }
}

class _Devices extends StatefulWidget {
  const _Devices({required this.c});
  final AppController c;
  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  late Future<List<SyncDevice>?> devices = widget.c.sync.devices();

  @override
  Widget build(BuildContext context) {
    final lang = widget.c.lang;
    final u = ui(lang), t = text(lang);
    final fmt = Fmt(lang);
    return Panel(
      child: FutureBuilder<List<SyncDevice>?>(
        future: devices,
        builder: (context, snap) {
          final list = snap.data;
          return Gap(space: 8, children: [
            Heading(u['syncDevices'], size: 17),
            if (snap.connectionState != ConnectionState.done)
              const LinearProgressIndicator()
            else if (list == null)
              Muted(u['syncOffline'], size: 13)
            else
              for (final d in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(d.name.toLowerCase().contains('ipad') ? Icons.tablet_mac : Icons.smartphone),
                  title: Text(d.me ? '${d.name} (${u['syncThisShort']})' : d.name),
                  subtitle: Text(fill(u['syncLastSeen'], {'time': fmt.dateTime(d.lastSeen)})),
                  trailing: d.me
                      ? null
                      : IconButton(
                          tooltip: u['syncRemoveDevice'],
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            if (await confirmDialog(context,
                                title: u['syncRemoveDevice'],
                                body: fill(u['syncRemoveDeviceText'], {'device': d.name}),
                                confirm: u['syncRemoveDevice'],
                                cancel: t.cancel)) {
                              await widget.c.sync.removeDevice(d);
                              setState(() => devices = widget.c.sync.devices());
                            }
                          },
                        ),
                ),
          ]);
        },
      ),
    );
  }
}

/// First device: name the account, then show the recovery code once.
Future<void> createAccount(BuildContext context, AppController c) async {
  final lang = c.lang;
  final u = ui(lang), t = text(lang);
  final name = TextEditingController(text: c.groups.name);
  final device = TextEditingController(text: defaultDeviceName(context));
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(u['syncCreate']),
      content: Gap(children: [
        TextField(
          controller: name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: u['syncAccountName'], helperText: u['syncAccountNameHelp']),
        ),
        TextField(
          controller: device,
          maxLength: 40,
          decoration: InputDecoration(labelText: u['syncDeviceName']),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(u['syncCreate'])),
      ],
    ),
  );
  final accountName = name.text.trim(), deviceName = device.text.trim();
  name.dispose();
  device.dispose();
  if (ok != true || accountName.isEmpty || deviceName.isEmpty) return;
  final code = await c.sync.createAccount(accountName, deviceName);
  if (code != null && context.mounted) await showRecoveryCode(context, c, code);
}

/// The recovery code, shown once, with copy and share.
Future<void> showRecoveryCode(BuildContext context, AppController c, String code) {
  final u = ui(c.lang);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(u['syncRecoveryTitle']),
      content: Gap(children: [
        Text(u['syncRecoveryShow']),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.palette.muted, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 1.5, height: 1.5)),
        ),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(u['copied'])));
            },
            icon: const Icon(Icons.copy, size: 17),
            label: Text(u['syncCopy']),
          ),
          OutlinedButton.icon(
            onPressed: () => shareText(fill(u['syncRecoveryShare'], {'code': code})),
            icon: const Icon(Icons.ios_share, size: 17),
            label: Text(u['share']),
          ),
        ]),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(u['syncRecoverySaved']))],
    ),
  );
}

/// On a device of the account: a short-lived code (and QR) for a new device.
Future<void> showPairing(BuildContext context, AppController c) async {
  final lang = c.lang;
  final u = ui(lang);
  final result = await c.sync.pairingCode();
  if (result == null || !context.mounted) return;
  final (code, expiresAt) = result;
  final until = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(expiresAt)).format(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(u['syncAddDevice']),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Gap(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(u['syncPairHelp'], textAlign: TextAlign.center),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: pairingLink(code), size: 190, backgroundColor: Colors.white),
            ),
            SelectableText(code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3)),
            Muted(fill(u['syncPairValid'], {'time': until}), size: 13),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(u['close']))],
    ),
  );
}

/// On a new device: enter the code from another device (or the recovery code).
Future<void> linkDevice(BuildContext context, AppController c) async {
  final lang = c.lang;
  final u = ui(lang);
  final input = await showDialog<(String, String, bool)>(
    context: context,
    builder: (_) => _LinkDialog(lang: lang, deviceName: defaultDeviceName(context)),
  );
  if (input == null) return;
  final (value, deviceName, recovery) = input;
  final result = recovery
      ? await c.sync.join(recoveryCode: value, deviceName: deviceName)
      : await c.sync.join(code: value, deviceName: deviceName);
  if (result != JoinResult.choosePlan || !context.mounted) return;
  final remote = c.sync.pendingRemote?.state;
  final mine = PlanView.of(c);
  final keepAccount = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(u['syncChooseTitle']),
      content: Text(fill(u['syncChooseText'], {
        'account': remote == null ? '–' : '${remote.done.length + (remote.previouslyRead?.length ?? 0)}',
        'device': mine == null ? '–' : '${mine.doneCount}',
      })),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(u['syncKeepDevice'])),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(u['syncKeepAccount'])),
      ],
    ),
  );
  await c.sync.choosePlan(keepAccount: keepAccount ?? true);
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.lang, required this.deviceName});
  final Lang lang;
  final String deviceName;
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final code = TextEditingController();
  late final device = TextEditingController(text: widget.deviceName);
  bool recovery = false;
  String error = '';

  @override
  void dispose() {
    code.dispose();
    device.dispose();
    super.dispose();
  }

  void submit() {
    final u = ui(widget.lang);
    final parsed = recovery ? parseRecoveryCode(code.text) : parsePairingCode(code.text);
    if (parsed == null || device.text.trim().isEmpty) {
      setState(() => error = parsed == null ? u['syncCodeInvalid'] : u['nameNeeded']);
      return;
    }
    Navigator.pop(context, (parsed, device.text.trim(), recovery));
  }

  @override
  Widget build(BuildContext context) {
    final u = ui(widget.lang), t = text(widget.lang);
    return AlertDialog(
      title: Text(u['syncLink']),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Gap(children: [
            Text(recovery ? u['syncLinkRecoveryHelp'] : u['syncLinkHelp']),
            TextField(
              controller: code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: recovery ? u['syncRecoveryLabel'] : u['syncCodeLabel'],
                hintText: recovery ? 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX' : 'ABCD-EFGH',
                suffixIcon: recovery
                    ? null
                    : IconButton(
                        tooltip: u['scan'],
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => ScanPage(lang: widget.lang, accept: (v) => parsePairingCode(v) != null),
                          ));
                          final parsed = raw == null ? null : parsePairingCode(raw);
                          if (parsed != null) setState(() => code.text = parsed);
                        },
                      ),
              ),
            ),
            TextField(
              controller: device,
              maxLength: 40,
              decoration: InputDecoration(labelText: u['syncDeviceName'], counterText: ''),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() {
                  recovery = !recovery;
                  error = '';
                  code.clear();
                }),
                child: Text(recovery ? u['syncUsePairing'] : u['syncUseRecovery']),
              ),
            ),
            if (error.isNotEmpty) Notice(text: error, kind: NoticeKind.error),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: submit, child: Text(u['syncLinkButton'])),
      ],
    );
  }
}
