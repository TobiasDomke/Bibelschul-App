import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/editions.dart';
import '../core/languages.dart';
import '../core/notes.dart';
import '../core/plan_code.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/feature_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import '../services/reminders.dart';
import 'bible52_weeks.dart';
import 'book_order_control.dart';
import 'dialogs.dart';
import 'previous_picker.dart';
import 'theme.dart';
import 'widgets.dart';

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Settings overview: five groups, each on its own page.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  void _open(BuildContext context, String title, List<Widget> Function(PlanView v) build) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final view = PlanView.of(c);
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              child: view == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          children: [
                            for (final (i, w) in build(view).indexed) ...[if (i > 0) const SizedBox(height: 14), w],
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), x = featureText(lang), f = bible52Text(lang);
    final groups = <(IconData, String, String, List<Widget> Function(PlanView))>[
      (Icons.notifications_none, x['groupReminders'], x['groupRemindersSub'], (v) => [RemindersCard(c: c)]),
      (
        Icons.menu_book_outlined,
        x['groupPlan'],
        x['groupPlanSub'],
        (v) => [
              if (v.fixed)
                Panel(
                  child:
                      Gap(children: [const Heading('Bibelleseplan 52', size: 19), Text(f.description), Muted(f.fixed)]),
                )
              else
                _EditionCard(c: c, state: v.state),
              _PlanManagement(c: c, state: v.state),
              SharePlanCard(c: c, state: v.state),
              JoinPlanCard(c: c),
              Panel(
                child: Builder(
                  builder: (context) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: t.replaceTitle, body: t.replaceText, confirm: t.confirm, cancel: t.cancel);
                        if (ok && context.mounted) {
                          c.update(() => c.newPlan = true);
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: Text(t.newPlan),
                    ),
                  ),
                ),
              ),
            ]
      ),
      (Icons.save_outlined, x['groupData'], x['groupDataSub'], (v) => [BackupCard(c: c), AutoBackupCard(c: c)]),
      (Icons.translate, x['groupAppearance'], x['groupAppearanceSub'], (v) => [_AppearanceCard(c: c, v: v)]),
      (Icons.info_outline, x['groupAbout'], x['groupAboutSub'], (v) => [_AboutCard(c: c, v: v)]),
    ];
    final u = ui(lang);
    return Gap(space: 14, children: [
      Heading(t.settings, size: 26),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (i, (icon, title, subtitle, build)) in groups.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: context.palette.border),
            ListTile(
              leading: Icon(icon, color: context.palette.primary),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, title, build),
            ),
          ],
        ]),
      ),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          leading: Icon(Icons.groups_outlined, color: context.palette.primary),
          title: Text(u['groupsTitle'], style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(u['groupsRowSub']),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => c.update(() {
            c.tab = 'stats';
            c.statsView = 'groups';
          }),
        ),
      ),
    ]);
  }
}

/// Reminder time, time zone and the local notifications.
class RemindersCard extends StatefulWidget {
  const RemindersCard({super.key, required this.c});
  final AppController c;
  @override
  State<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<RemindersCard> {
  String status = '';

  Future<String?> _pickTime(BuildContext context, String current) async {
    final [h, m] = current.split(':').map(int.parse).toList();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final t = text(lang), push = pushText(lang), n = nativeText(lang), x = featureText(lang);
    final palette = context.palette;
    final zones = {
      c.zone,
      'Europe/Berlin',
      'Europe/Moscow',
      'Europe/Kyiv',
      'Europe/London',
      'America/New_York',
      'Asia/Almaty',
      'UTC',
    }.where(isValidTimezone).toList();
    Future<ReadingState?> save() async {
      final s = await c.mutate({'action': 'settings', 'time': c.reminderTime, 'timezone': c.zone, 'lang': lang.name});
      if (s != null) c.update(() => c.message = 'saved');
      return s;
    }

    final enabled = c.prefs.remindersEnabled;
    final s = c.state;
    final next = enabled && s != null
        ? Reminders.plan(s, evening: c.prefs.eveningReminder, eveningTime: c.prefs.eveningTime).firstOrNull
        : null;
    final changed = s != null && (s.config.time != c.reminderTime || s.config.timezone != c.zone);
    return Panel(
      child: Gap(children: [
        Icon(Icons.notifications_none, color: palette.primary, size: 24),
        Heading(t.reminders, size: 19),
        Muted(n.reminderIntro),
        FieldLabel(t.time),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(50)),
          onPressed: () async {
            final picked = await _pickTime(context, c.reminderTime);
            if (picked != null) c.update(() => c.reminderTime = picked);
          },
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(c.reminderTime),
        ),
        Details(summary: '${t.timezone}: ${c.zone}', children: [
          Muted(ui(lang)['zoneHelp'], size: 13),
          LabeledDropdown<String>(
            label: t.timezone,
            value: c.zone,
            items: [for (final z in zones) (z, z)],
            onChanged: (z) => c.update(() => c.zone = z),
          ),
        ]),
        if (changed) FilledButton(onPressed: c.busy ? null : save, child: Text(c.busy ? t.saving : t.save)),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(n.reminderTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(enabled ? push.active : push.inactive),
          value: enabled,
          onChanged: (on) async {
            if (on) {
              final ok = await c.enableReminders();
              setState(() => status = ok ? n.reminderSaved : n.reminderBlocked);
            } else {
              await c.disableReminders();
              setState(() => status = '');
            }
          },
        ),
        if (enabled) ...[
          Muted(x['smartReminder'], size: 13),
          if (next != null) Muted('${push.next}: ${Fmt(lang).dateTime(next.$1.millisecondsSinceEpoch)}', size: 13),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(x['evening']),
            subtitle: Text(x['eveningHelp']),
            value: c.prefs.eveningReminder,
            onChanged: (on) => c.setEvening(enabled: on),
          ),
          if (c.prefs.eveningReminder)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(50)),
              onPressed: () async {
                final picked = await _pickTime(context, c.prefs.eveningTime);
                if (picked != null) await c.setEvening(time: picked);
              },
              icon: const Icon(Icons.nights_stay_outlined, size: 18),
              label: Text('${x['eveningTime']}: ${c.prefs.eveningTime}'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Reminders.instance.showTest(lang);
                setState(() => status = n.testShown);
              },
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: Text(push.test),
            ),
          ),
        ],
        FinePrint(n.reminderPrivacy),
        if (status.isNotEmpty) Notice(text: status),
      ]),
    );
  }
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({required this.c, required this.state});
  final AppController c;
  final ReadingState state;
  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final e = experienceText(lang), t = text(lang);
    return Panel(
      child: Gap(children: [
        Heading(e.edition, size: 19),
        LabeledDropdown<String>(
          label: e.switchEdition,
          value: state.config.edition ?? 'schlachter2000',
          enabled: !c.busy && state.timer == null,
          items: [for (final id in editionIds) (id, editions[id]!.name)],
          onChanged: (selected) async {
            if (selected == (state.config.edition ?? 'schlachter2000')) return;
            final ok = await confirmDialog(
              context,
              title: e.switchEdition,
              body: e.switchHelp,
              extra: Text('${editionName(state.config.edition)} → ${editions[selected]!.name}'),
              confirm: t.save,
              cancel: t.cancel,
            );
            if (ok) {
              await c.mutate({'action': 'edition', 'edition': selected});
            } else {
              c.update(() {});
            }
          },
        ),
        FinePrint(ui(lang)['editionHelp']),
        if (state.editionReview?.isNotEmpty ?? false)
          Notice(
            kind: NoticeKind.warning,
            actions: [
              OutlinedButton(
                onPressed: c.busy ? null : () => c.mutate({'action': 'review-edition'}),
                child: Text(e.reviewed),
              ),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.reviewEdition),
              Text(state.editionReview!.join(' · ')),
            ]),
          ),
      ]),
    );
  }
}

class _PlanManagement extends StatelessWidget {
  const _PlanManagement({required this.c, required this.state});
  final AppController c;
  final ReadingState state;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final fixed = isBible52(state.config);
    final p = planText(lang);
    final locked = state.timer != null || (fixed && state.pace?.draft != null);
    return Panel(
      child: Gap(children: [
        Heading(p.manage, size: 19),
        Muted(fixed ? 'Bibelleseplan 52' : '${p[state.config.scope ?? 'bible']} · ${p[state.config.order ?? 'canonical']}'),
        Text(fill(p.selected, {'count': state.previouslyRead?.length ?? 0})),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: c.busy || locked
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => _EditPrevious(c: c, state: state),
                    )),
            child: Text(p.editPrevious),
          ),
          if (!fixed)
            OutlinedButton(
              onPressed: c.busy ? null : () => showDeadlineDialog(context, c),
              child: Text(deadlineText(lang).edit),
            ),
        ]),
        if (locked) FinePrint(p.stopFirst),
      ]),
    );
  }
}

class _EditPrevious extends StatefulWidget {
  const _EditPrevious({required this.c, required this.state});
  final AppController c;
  final ReadingState state;
  @override
  State<_EditPrevious> createState() => _EditPreviousState();
}

class _EditPreviousState extends State<_EditPrevious> {
  late List<int> previous = [...?widget.state.previouslyRead];

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final p = planText(lang), t = text(lang), f = bible52Text(lang);
    final fixed = isBible52(widget.state.config);
    final locked = widget.state.done.keys.toList();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(p.editPrevious)),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Muted(fixed ? f.progressHelp : p.previousEditHelp),
            const SizedBox(height: 12),
            if (fixed)
              Bible52Weeks(
                value: previous,
                lang: lang,
                locked: locked,
                disabled: c.busy,
                onChanged: (x) => setState(() => previous = x),
              )
            else
              PreviousPicker(
                config: widget.state.config,
                value: previous,
                lang: lang,
                locked: locked,
                disabled: c.busy,
                onChanged: (x) => setState(() => previous = x),
              ),
            if (c.error.isNotEmpty) ...[const SizedBox(height: 12), Notice(text: t.error, kind: NoticeKind.error)],
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: c.busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: c.busy
                      ? null
                      : () async {
                          final navigator = Navigator.of(context);
                          if (await c.mutate({'action': 'previous', 'previouslyRead': previous}) != null) {
                            navigator.pop();
                          }
                        },
                  child: Text(c.busy ? t.saving : t.save),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Share the plan settings with a class or group (QR code or text code).
class SharePlanCard extends StatefulWidget {
  const SharePlanCard({super.key, required this.c, required this.state});
  final AppController c;
  final ReadingState state;
  @override
  State<SharePlanCard> createState() => _SharePlanCardState();
}

class _SharePlanCardState extends State<SharePlanCard> {
  late final name = TextEditingController(text: widget.c.prefs.groupName(widget.state.id));

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final x = featureText(c.lang);
    String code() {
      c.prefs.setGroupName(widget.state.id, name.text.trim());
      return encodePlanCode(widget.state.config, name.text);
    }

    // A link: the phone camera opens the Leseweg page instead of showing raw text.
    String link() => 'https://leseweg.pages.dev/#plan=${code()}';

    return Panel(
      child: Gap(children: [
        Icon(Icons.groups_outlined, color: context.palette.primary),
        Heading(x['share'], size: 19),
        Muted(x['shareHelp']),
        TextField(
          controller: name,
          maxLength: 80,
          decoration: InputDecoration(labelText: x['groupName'], counterText: ''),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () {
              final value = link();
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(name.text.trim().isEmpty ? x['share'] : name.text.trim()),
                  actionsOverflowDirection: VerticalDirection.up,
                  content: SizedBox(
                    width: 280,
                    child: Gap(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(data: value, size: 240, backgroundColor: Colors.white),
                      ),
                      Text(ui(c.lang)['shareQrHelp'], textAlign: TextAlign.center),
                    ]),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(x['close']))],
                ),
              );
            },
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: Text(x['shareShow']),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await shareText('${x['shareMessage']}\n\n${code()}\n${link()}');
              if (!ok && context.mounted) _snack(context, nativeText(c.lang).shareFailed);
            },
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(x['shareSend']),
          ),
        ]),
      ]),
    );
  }
}

/// Join a plan received from a group.
class JoinPlanCard extends StatelessWidget {
  const JoinPlanCard({super.key, required this.c});
  final AppController c;

  Future<void> _use(BuildContext context, String raw) async {
    final lang = c.lang;
    final x = featureText(lang), t = text(lang), p = planText(lang);
    final plan = decodePlanCode(raw, time: c.reminderTime, timezone: c.zone);
    if (plan == null) {
      _snack(context, x['joinInvalid']);
      return;
    }
    final config = isBible52(plan.config) ? bible52Config(plan.config) : plan.config;
    final days = createPlan(config);
    final fmt = Fmt(lang);
    final summary = [
      if (plan.name.isNotEmpty) plan.name,
      isBible52(config) ? 'Bibelleseplan 52' : '${p[config.scope ?? 'bible']} · ${p[config.order ?? 'canonical']}',
      editionName(config.edition),
      '${x['start']}: ${fmt.date(days.first.date, long: true)} · ${t.target}: ${fmt.date(days.last.date, long: true)}',
    ].join('\n');
    final ok = await confirmDialog(
      context,
      title: x['joinTitle'],
      body: summary,
      extra: c.state == null ? null : Notice(kind: NoticeKind.warning, text: x['joinReplace']),
      confirm: x['joinCreate'],
      cancel: t.cancel,
    );
    if (!ok || !context.mounted) return;
    final created = await c.joinPlan(plan);
    if (created != null && context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> paste(BuildContext context) async {
    final x = featureText(c.lang);
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final controller = TextEditingController(text: clip.contains('LESEWEG1.') ? clip : '');
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(x['joinPaste']),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: x['joinPasteHint']),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(text(c.lang).cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(x['joinCreate'])),
        ],
      ),
    );
    controller.dispose();
    if (raw != null && raw.trim().isNotEmpty && context.mounted) await _use(context, raw);
  }

  Future<void> scan(BuildContext context) async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ScanPage(lang: c.lang, accept: (v) => v.contains('LESEWEG1.')),
    ));
    if (raw != null && context.mounted) await _use(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    final x = featureText(c.lang);
    return Panel(
      child: Gap(children: [
        Icon(Icons.qr_code_scanner, color: context.palette.primary),
        Heading(x['join'], size: 19),
        Muted(x['joinHelp']),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => scan(context),
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(x['joinScan']),
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => paste(context),
            icon: const Icon(Icons.content_paste, size: 18),
            label: Text(x['joinPaste']),
          ),
        ]),
      ]),
    );
  }
}

/// Camera page that returns the first QR code [accept] likes.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.lang, required this.accept});
  final Lang lang;
  final bool Function(String value) accept;
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    final x = featureText(widget.lang);
    return Scaffold(
      appBar: AppBar(title: Text(x['joinScan'])),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (done) return;
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && widget.accept(value)) {
                done = true;
                Navigator.pop(context, value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(x['cameraDenied'], textAlign: TextAlign.center),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: SafeArea(child: Notice(text: x['cameraHelp'])),
        ),
      ]),
    );
  }
}

/// Backup export and restore (app/backup-controls.tsx); includes notes.
class BackupCard extends StatefulWidget {
  const BackupCard({super.key, required this.c});
  final AppController c;
  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool working = false;
  String error = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), n = nativeText(lang), x = featureText(lang);
    final state = c.state;
    final history = c.prefs.backupStatus(state?.id);
    return Panel(
      child: Gap(children: [
        Icon(Icons.save_outlined, color: context.palette.primary),
        Heading(t.localData, size: 19),
        Muted(n.localDataSub),
        if (state != null)
          FinePrint(history.exported > 0 ? '${e.lastExport}: ${Fmt(lang).dateTime(history.exported)}' : e.neverExport),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (state != null)
            OutlinedButton.icon(
              onPressed: c.busy || working
                  ? null
                  : () async {
                      setState(() {
                        error = '';
                        working = true;
                      });
                      try {
                        final latest = await c.store.read();
                        if (latest == null) throw const AppError('backup');
                        final ok = await shareFile(makeAppBackup(latest, lang, c.backupTheme, c.notes),
                            'leseweg-sicherung-${today(latest.config.timezone)}.json', 'application/json');
                        if (!ok) throw const AppError('share');
                        await c.prefs.recordBackup(latest.id, 'exported');
                      } catch (_) {
                        error = t.backupSaveError;
                      } finally {
                        if (mounted) setState(() => working = false);
                      }
                    },
              icon: const Icon(Icons.ios_share, size: 17),
              label: Text(t.backupSave),
            ),
          OutlinedButton.icon(
            onPressed: c.busy || working ? null : () => _import(context),
            icon: const Icon(Icons.file_open_outlined, size: 17),
            label: Text(t.backupLoad),
          ),
        ]),
        FinePrint('${n.backupNote} ${n.backupCaution}'),
        FinePrint(n.importHelp),
        if (c.notes.isNotEmpty) FinePrint(x['backupNotesHint']),
        if (error.isNotEmpty) Notice(text: error, kind: NoticeKind.error),
      ]),
    );
  }

  Future<void> _import(BuildContext context) async {
    setState(() {
      error = '';
      working = true;
    });
    final failed = await importBackupFlow(context, widget.c);
    if (mounted) {
      setState(() {
        working = false;
        error = failed ?? '';
      });
    }
  }
}

/// Picks a backup file, asks for confirmation and restores it. Returns an
/// error text, or null when it worked or was cancelled.
Future<String?> importBackupFlow(BuildContext context, AppController c) async {
  final lang = c.lang;
  final t = text(lang);
  AppBackup? backup;
  try {
    backup = await pickBackup();
  } catch (_) {
    return t.backupInvalid;
  }
  if (backup == null || !context.mounted) return null;
  final b = backup.backup;
  final ok = await confirmDialog(
    context,
    title: t.backupRestoreTitle,
    body: t.backupRestoreText,
    extra: Text('${Fmt(lang).date(b.exportedAt.substring(0, 10))} · ${editionName(b.state.config.edition)} · '
        '${b.state.done.length + (b.state.previouslyRead?.length ?? 0)} ${t.chapters} · ${t.read}'),
    confirm: t.backupRestore,
    cancel: t.cancel,
  );
  if (!ok) return null;
  try {
    await c.restoreBackup(backup);
    return null;
  } catch (_) {
    return t.backupSaveError;
  }
}

/// On the start screen: bring back a backup or take over a group's plan,
/// without filling the page with both full cards.
class ExistingPlanCard extends StatefulWidget {
  const ExistingPlanCard({super.key, required this.c});
  final AppController c;
  @override
  State<ExistingPlanCard> createState() => _ExistingPlanCardState();
}

class _ExistingPlanCardState extends State<ExistingPlanCard> {
  String error = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final u = ui(lang), t = text(lang);
    final join = JoinPlanCard(c: c);
    return Panel(
      child: Gap(space: 10, children: [
        Heading(u['existing'], size: 17),
        Muted(u['existingHelp'], size: 13.5),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    final failed = await importBackupFlow(context, c);
                    if (mounted) setState(() => error = failed ?? '');
                  },
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: Text(t.backupLoad),
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => join.scan(context),
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(u['scanPlan']),
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => join.paste(context),
            icon: const Icon(Icons.content_paste, size: 18),
            label: Text(u['pastePlan']),
          ),
        ]),
        if (error.isNotEmpty) Notice(text: error, kind: NoticeKind.error),
      ]),
    );
  }
}

class AutoBackupCard extends StatelessWidget {
  const AutoBackupCard({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) {
    final x = featureText(c.lang);
    final last = c.prefs.lastAutoBackup;
    return Panel(
      child: Gap(children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(x['autoBackup'], style: const TextStyle(fontWeight: FontWeight.w600)),
          value: c.prefs.autoBackup,
          onChanged: c.setAutoBackup,
        ),
        Muted(x['autoBackupHelp'], size: 13),
        FinePrint(last > 0 ? fill(x['autoBackupLast'], {'date': Fmt(c.lang).dateTime(last)}) : x['autoBackupNone']),
      ]),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.c, required this.v});
  final AppController c;
  final PlanView v;
  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang);
    final s = v.state;
    return Panel(
      child: Gap(children: [
        LabeledDropdown<Lang>(
          label: t.language,
          value: lang,
          enabled: !c.busy,
          items: [for (final l in Lang.values) (l, languageLabels[l]!)],
          onChanged: c.changeLanguage,
        ),
        LabeledDropdown<String>(
          label: t.theme,
          value: c.theme,
          items: [('system', ui(lang)['themeSystem']), ('light', t.light), ('dark', t.dark)],
          onChanged: c.setTheme,
        ),
        if (!v.fixed)
          Details(summary: ui(lang)['bookOrder'], children: [
            Muted(ui(lang)['bookOrderHelp'], size: 13),
            BookOrderControl(
              config: s.config,
              lang: lang,
              disabled: c.busy,
              pending: s.pendingBookOrder,
              onChanged: (choice) => c.mutate({'action': 'book-order', 'choice': choice, 'lang': lang.name}),
            ),
          ]),
      ]),
    );
  }
}

/// Explanations that the web app showed on every screen, collected in one place.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.c, required this.v});
  final AppController c;
  final PlanView v;
  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), p = planText(lang), f = bible52Text(lang);
    final time = readingTimeText(lang);
    Widget section(String title, List<String> body) => Gap(space: 6, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          for (final b in body) Text(b),
        ]);
    return Panel(
      child: Gap(space: 18, children: [
        section(t.plan, [v.fixed ? f.fixed : t.adaptiveHint, t.finishExplanation]),
        section(t.paceTitle, [e.paceHelp, t.timerNote]),
        section(time.title, [time.help]),
        section(e.edition, [e.editionHelp, e.approxWeights]),
        if (!v.fixed && v.state.config.order == 'chronological') section(p.chronological, [p.contextNote]),
        const FinePrint('Wortzahlen: Luther 1912 · Public Domain · github.com/midvash/bible-data'),
        FinePrint('Bibelleseplan 52: ${f.description}'),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, info) => info.hasData
              ? FinePrint('Leseweg · ${fill(ui(lang)['version'], {'version': '${info.data!.version} (${info.data!.buildNumber})'})}')
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}
