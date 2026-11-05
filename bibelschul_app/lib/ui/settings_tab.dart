import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/backup.dart';
import '../core/editions.dart';
import '../core/exports.dart';
import '../core/languages.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../core/util.dart';
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

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), f = bible52Text(lang);
    final s = v.state;
    return Gap(space: 14, children: [
      const Eyebrow('LESEWEG'),
      Heading(t.settings, size: 26),
      _RemindersCard(c: c),
      if (v.fixed)
        Panel(
          child: Gap(children: [const Heading('Bibelleseplan 52', size: 19), Text(f.description), Muted(f.fixed)]),
        )
      else
        _EditionCard(c: c, state: s),
      _PlanManagement(c: c, state: s),
      BackupCard(c: c),
      Panel(
        child: Gap(children: [
          Heading(t.language, size: 19),
          LabeledDropdown<Lang>(
            label: t.language,
            value: lang,
            enabled: !c.busy,
            items: [for (final l in Lang.values) (l, languageLabels[l]!)],
            onChanged: c.changeLanguage,
          ),
          FinePrint(v.fixed ? f.fixed : e.editionHelp),
          if (!v.fixed)
            Details(summary: e.advanced, children: [
              BookOrderControl(
                config: s.config,
                lang: lang,
                disabled: c.busy,
                pending: s.pendingBookOrder,
                onChanged: (choice) => c.mutate({'action': 'book-order', 'choice': choice, 'lang': lang.name}),
              ),
            ]),
          LabeledDropdown<String>(
            label: t.theme,
            value: c.theme,
            items: [('light', t.light), ('dark', t.dark)],
            onChanged: c.setTheme,
          ),
        ]),
      ),
      Panel(
        child: Gap(children: [
          Muted(editionName(s.config.edition)),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: t.replaceTitle, body: t.replaceText, confirm: t.confirm, cancel: t.cancel);
              if (ok) c.update(() => c.newPlan = true);
            },
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(t.newPlan),
          ),
          Details(summary: t.explain, children: [
            Text(e.approxWeights),
            const FinePrint('bible-data · Luther 1912 (github.com/midvash/bible-data)'),
          ]),
        ]),
      ),
    ]);
  }
}

class _RemindersCard extends StatefulWidget {
  const _RemindersCard({required this.c});
  final AppController c;
  @override
  State<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<_RemindersCard> {
  String status = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final t = text(lang), push = pushText(lang), n = nativeText(lang);
    final palette = context.palette;
    final zones = {c.zone, 'Europe/Berlin', 'Europe/Moscow', 'Europe/Kyiv', 'Europe/London', 'America/New_York', 'Asia/Almaty', 'UTC'}
        .where(isValidTimezone)
        .toList();
    final [h, m] = c.reminderTime.split(':').map(int.parse).toList();
    Future<ReadingState?> save() async {
      final s = await c.mutate({'action': 'settings', 'time': c.reminderTime, 'timezone': c.zone, 'lang': lang.name});
      if (s != null) c.update(() => c.message = 'saved');
      return s;
    }

    final enabled = c.prefs.remindersEnabled;
    final next = enabled && c.state != null
        ? Reminders.nextOccurrence(c.state!.config.time, c.state!.config.timezone)
        : null;
    return Panel(
      child: Gap(children: [
        Icon(Icons.notifications_none, color: palette.primary, size: 24),
        Heading(t.reminders, size: 19),
        FieldLabel(t.time),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(50)),
          onPressed: () async {
            final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
            if (picked != null) {
              c.update(() => c.reminderTime =
                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(c.reminderTime),
        ),
        LabeledDropdown<String>(
          label: t.timezone,
          value: c.zone,
          items: [for (final z in zones) (z, z)],
          onChanged: (z) => c.update(() => c.zone = z),
        ),
        FilledButton(onPressed: c.busy ? null : save, child: Text(c.busy ? t.saving : t.save)),
        const Divider(),
        Heading(n.reminderTitle, size: 17),
        Muted(n.reminderIntro),
        FinePrint(n.reminderPrivacy),
        Text(enabled ? push.active : push.inactive, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (next != null) Muted('${push.next}: ${Fmt(lang).dateTime(next.millisecondsSinceEpoch)}'),
        if (enabled) Muted(push.savedTime),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!enabled)
            FilledButton(
              onPressed: () async {
                final ok = await c.enableReminders();
                setState(() => status = ok ? n.reminderSaved : n.reminderBlocked);
              },
              child: Text(push.enable),
            )
          else ...[
            OutlinedButton(
              onPressed: () async {
                await Reminders.instance.showTest(lang);
                setState(() => status = n.testShown);
              },
              child: Text(push.test),
            ),
            TextButton(
              onPressed: () async {
                await c.disableReminders();
                setState(() => status = push.inactive);
              },
              child: Text(push.disable),
            ),
          ],
        ]),
        if (status.isNotEmpty) Notice(text: status),
        const Divider(),
        Details(summary: t.calendar, children: [
          Muted(t.calendarSub),
          OutlinedButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    final s = await save();
                    if (s == null) return;
                    final ok = await shareFile(calendarFile(s, lang), 'leseweg.ics', 'text/calendar');
                    if (!ok && context.mounted) _snack(context, n.shareFailed);
                  },
            icon: const Icon(Icons.ios_share, size: 17),
            label: Text(t.download),
          ),
          FinePrint(t.calendarNote),
        ]),
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
        Text(editionName(state.config.edition), style: const TextStyle(fontWeight: FontWeight.w700)),
        Muted(e.editionHelp),
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
        if (state.editionReview?.isNotEmpty ?? false)
          Notice(
            kind: NoticeKind.warning,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.reviewEdition),
              Text(state.editionReview!.join(' · ')),
            ]),
            actions: [
              OutlinedButton(
                onPressed: c.busy ? null : () => c.mutate({'action': 'review-edition'}),
                child: Text(e.reviewed),
              ),
            ],
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
                child: OutlinedButton(
                    onPressed: c.busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
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

/// Backup export and restore (app/backup-controls.tsx).
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
    final t = text(lang), e = experienceText(lang), n = nativeText(lang);
    final state = c.state;
    final history = c.prefs.backupStatus(state?.id);
    return Panel(
      child: Gap(children: [
        Icon(Icons.save_outlined, color: context.palette.primary),
        Heading(t.localData, size: 19),
        Muted(t.localDataSub),
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
                        final ok = await shareFile(makeBackup(latest, lang, c.theme),
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
        FinePrint('${t.backupNote} ${e.backupCaution}'),
        FinePrint(n.importHelp),
        if (error.isNotEmpty) Notice(text: error, kind: NoticeKind.error),
      ]),
    );
  }

  Future<void> _import(BuildContext context) async {
    final c = widget.c;
    final lang = c.lang;
    final t = text(lang);
    setState(() {
      error = '';
      working = true;
    });
    Backup? backup;
    try {
      backup = await pickBackup();
    } catch (_) {
      error = t.backupInvalid;
    }
    if (mounted) setState(() => working = false);
    if (backup == null || !context.mounted) return;
    final b = backup;
    final ok = await confirmDialog(
      context,
      title: t.backupRestoreTitle,
      body: t.backupRestoreText,
      extra: Text('${Fmt(lang).date(b.exportedAt.substring(0, 10))} · ${editionName(b.state.config.edition)} · '
          '${b.state.done.length + (b.state.previouslyRead?.length ?? 0)} ${t.chapters} · ${t.read}'),
      confirm: t.backupRestore,
      cancel: t.cancel,
    );
    if (!ok) return;
    setState(() => working = true);
    try {
      await c.restoreBackup(b);
    } catch (_) {
      error = t.backupSaveError;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }
}
