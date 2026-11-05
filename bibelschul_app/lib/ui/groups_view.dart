import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/controller.dart';
import '../app/groups.dart';
import '../app/plan_view.dart';
import '../core/languages.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import '../services/groups_api.dart';
import 'dialogs.dart';
import 'settings_tab.dart' show ScanPage;
import 'theme.dart';
import 'widgets.dart';

/// What a group ranking compares.
enum Metric { chapters, progress, week, streak, speed, time }

/// Reading groups: compare numbers with a class or friends (opt-in).
class GroupsView extends StatefulWidget {
  const GroupsView({super.key, required this.c});
  final AppController c;
  @override
  State<GroupsView> createState() => _GroupsViewState();
}

class _GroupsViewState extends State<GroupsView> {
  Metric metric = Metric.chapters;

  GroupsController get g => widget.c.groups;

  @override
  void initState() {
    super.initState();
    // Fresh numbers when the page opens, at most once a minute.
    if (g.joined && DateTime.now().millisecondsSinceEpoch - g.syncedAt > 60000) {
      WidgetsBinding.instance.addPostFrameCallback((_) => g.refresh(PlanView.of(widget.c)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: g, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final u = ui(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final groups = g.groups;
    final errorText = g.error.isEmpty ? null : groupErrorText(lang, g.error, cached: groups.isNotEmpty);

    if (groups.isEmpty) {
      return Gap(space: 14, children: [
        Panel(
          child: Gap(space: 12, children: [
            Icon(Icons.groups_outlined, color: palette.primary, size: 28),
            Heading(u['groupsTitle'], size: 21),
            Text(u['groupsIntro']),
            Notice(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline, size: 18, color: palette.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(u['groupsPrivacy'])),
              ]),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: g.loading ? null : () => _create(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(u['createGroup']),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: g.loading ? null : () => _join(context),
                icon: const Icon(Icons.login, size: 18),
                label: Text(u['joinGroup']),
              ),
            ),
            FinePrint(u['friendsHint']),
            if (g.loading) const LinearProgressIndicator(),
            if (errorText != null) Notice(text: errorText, kind: NoticeKind.error),
          ]),
        ),
      ]);
    }

    return Gap(space: 14, children: [
      Row(children: [
        Expanded(
          child: Muted(
            g.loading
                ? u['groupsLoading']
                : (g.syncedAt > 0 ? fill(u['groupsUpdated'], {'time': fmt.dateTime(g.syncedAt)}) : ''),
            size: 13,
          ),
        ),
        IconButton(
          tooltip: u['refresh'],
          onPressed: g.loading ? null : () => g.refresh(PlanView.of(c)),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      if (g.loading) const LinearProgressIndicator(),
      if (errorText != null) Notice(text: errorText, kind: g.error == 'offline' ? NoticeKind.info : NoticeKind.error),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final m in Metric.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(u['rank_${m.name}']),
                selected: metric == m,
                onSelected: (_) => setState(() => metric = m),
              ),
            ),
        ]),
      ),
      if (metric == Metric.speed) FinePrint(u['rankSpeedHelp']),
      for (final group in groups) _GroupCard(c: c, group: group, metric: metric),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: g.loading ? null : () => _join(context),
          icon: const Icon(Icons.login, size: 18),
          label: Text(u['joinGroup']),
        ),
        OutlinedButton.icon(
          onPressed: g.loading ? null : () => _create(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(u['createGroup']),
        ),
      ]),
      Panel(
        child: Gap(space: 10, children: [
          Heading(u['yourProfile'], size: 17),
          Row(children: [
            Expanded(child: Text(g.name.isEmpty ? '–' : g.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(onPressed: g.loading ? null : () => _rename(context), child: Text(u['change'])),
          ]),
          FinePrint(u['groupsPrivacy']),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: palette.destructive),
              onPressed: g.loading
                  ? null
                  : () async {
                      final ok = await confirmDialog(context,
                          title: u['deleteAll'], body: u['deleteAllText'], confirm: u['deleteAll'], cancel: text(lang).cancel);
                      if (ok) await g.deleteAll();
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(u['deleteAll']),
            ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _create(BuildContext context) async {
    final u = ui(widget.c.lang);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _GroupForm(lang: widget.c.lang, name: g.name, title: u['createTitle'], create: true),
    );
    if (result == null || !context.mounted) return;
    if (await g.create(result.$1, result.$2, PlanView.of(widget.c)) && context.mounted) {
      final created = g.groups.last;
      await showInvite(context, widget.c, created);
    }
  }

  Future<void> _join(BuildContext context) async {
    final u = ui(widget.c.lang);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _GroupForm(lang: widget.c.lang, name: g.name, title: u['joinTitle'], create: false),
    );
    if (result == null) return;
    await g.join(result.$1, result.$2, PlanView.of(widget.c));
  }

  Future<void> _rename(BuildContext context) async {
    final lang = widget.c.lang;
    final u = ui(lang), t = text(lang);
    final controller = TextEditingController(text: g.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(u['yourName']),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(helperText: u['yourNameHelp']),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.save)),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) await g.setName(value, PlanView.of(widget.c));
  }
}

/// Human text for a service error code.
String groupErrorText(Lang lang, String code, {bool cached = false}) {
  final u = ui(lang);
  return switch (code) {
    'offline' => cached ? u['groupsOffline'] : u['groupsOfflineEmpty'],
    'group_not_found' || 'invalid_code' => u['codeInvalid'],
    'group_full' => u['groupFull'],
    'too_many_groups' => u['tooManyGroups'],
    'invalid_name' || 'invalid_group_name' => u['nameInvalid'],
    'rate_limited' => u['rateLimited'],
    'forbidden' => u['forbidden'],
    _ => u['serviceDown'],
  };
}

/// Shows the invitation: QR code, code to read aloud, share button.
Future<void> showInvite(BuildContext context, AppController c, ReadingGroup group) {
  final lang = c.lang;
  final u = ui(lang);
  final link = groupInviteLink(group.code);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(fill(u['inviteTitle'], {'name': group.name})),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Gap(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: link, size: 200, backgroundColor: Colors.white),
            ),
            SelectableText(group.code,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3)),
            Text(u['inviteHelp'], textAlign: TextAlign.center),
          ]),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: group.code));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(u['copied'])));
          },
          child: Text(u['copyCode']),
        ),
        FilledButton.icon(
          onPressed: () async {
            final ok = await shareText(fill(u['inviteMessage'], {'name': group.name, 'code': group.code, 'link': link}));
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nativeText(lang).shareFailed)));
            }
          },
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(u['share']),
        ),
      ],
    ),
  );
}

/// Create (group name + own name) or join (code + own name).
class _GroupForm extends StatefulWidget {
  const _GroupForm({required this.lang, required this.name, required this.title, required this.create});
  final Lang lang;
  final String name, title;
  final bool create;
  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final first = TextEditingController();
  late final member = TextEditingController(text: widget.name);
  String error = '';

  @override
  void initState() {
    super.initState();
    if (!widget.create) {
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        final code = parseGroupCode(data?.text ?? '');
        if (code != null && first.text.isEmpty && mounted) setState(() => first.text = code);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    first.dispose();
    member.dispose();
    super.dispose();
  }

  void _submit() {
    final u = ui(widget.lang);
    final value = first.text.trim();
    final name = member.text.trim();
    if (widget.create ? value.isEmpty : parseGroupCode(value) == null) {
      setState(() => error = widget.create ? u['nameNeeded'] : u['codeInvalid']);
      return;
    }
    if (name.isEmpty) {
      setState(() => error = u['nameNeeded']);
      return;
    }
    Navigator.pop(context, (widget.create ? value : parseGroupCode(value)!, name));
  }

  @override
  Widget build(BuildContext context) {
    final u = ui(widget.lang), t = text(widget.lang);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Gap(children: [
            TextField(
              controller: first,
              autofocus: true,
              maxLength: widget.create ? 60 : 30,
              textCapitalization: widget.create ? TextCapitalization.sentences : TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: widget.create ? u['groupNameLabel'] : u['codeLabel'],
                hintText: widget.create ? u['groupNameHint'] : 'ABCD-EFGH',
                counterText: '',
                suffixIcon: widget.create
                    ? null
                    : IconButton(
                        tooltip: u['scan'],
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => ScanPage(lang: widget.lang, accept: (v) => parseGroupCode(v) != null),
                          ));
                          final code = raw == null ? null : parseGroupCode(raw);
                          if (code != null) setState(() => first.text = code);
                        },
                      ),
              ),
            ),
            TextField(
              controller: member,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: u['yourName'], helperText: u['yourNameHelp'], counterText: ''),
              onSubmitted: (_) => _submit(),
            ),
            if (error.isNotEmpty) Notice(text: error, kind: NoticeKind.error),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(widget.create ? u['createGroup'] : u['joinGroup'])),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.c, required this.group, required this.metric});
  final AppController c;
  final ReadingGroup group;
  final Metric metric;

  num? _value(MemberStats? s) => switch (metric) {
        _ when s == null => null,
        Metric.chapters => s.chapters,
        Metric.progress => s.percent,
        Metric.week => s.weekChapters,
        Metric.streak => s.streak,
        Metric.speed => s.wpm,
        Metric.time => s.minutes,
      };

  String _format(num? value) {
    final lang = c.lang;
    final u = ui(lang), fmt = Fmt(lang);
    if (value == null) return '–';
    return switch (metric) {
      Metric.chapters || Metric.week => fill(u['valueChapters'], {'n': fmt.number(value)}),
      Metric.progress => '${value < 1 && value > 0 ? '< 1' : fmt.number(value.floor())} %',
      Metric.streak => fill(value == 1 ? u['valueDay'] : u['valueDays'], {'n': fmt.number(value)}),
      Metric.speed => fill(u['valueSpeed'], {'n': fmt.number(value)}),
      Metric.time => fmt.time(value * 60),
    };
  }

  String _lastRead(String? date) {
    final u = ui(c.lang);
    if (date == null) return u['neverRead'];
    final v = PlanView.of(c);
    final today = v?.currentDate ?? date;
    final days = daysBetween(date, today);
    return fill(u['lastRead'], {
      'when': days <= 0 ? u['whenToday'] : (days == 1 ? u['whenYesterday'] : fill(u['whenDaysAgo'], {'n': days})),
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final u = ui(lang), t = text(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final g = c.groups;
    final ranked = [...group.members]..sort((a, b) {
        final va = _value(a.stats), vb = _value(b.stats);
        if (va == null && vb == null) return a.name.compareTo(b.name);
        if (va == null) return 1;
        if (vb == null) return -1;
        return vb.compareTo(va);
      });
    final shared = group.members.where((m) => m.stats != null);
    final together = shared.fold<int>(0, (n, m) => n + m.stats!.chapters);
    final week = shared.fold<int>(0, (n, m) => n + m.stats!.weekChapters);

    Future<void> menu(String action) async {
      switch (action) {
        case 'invite':
          await showInvite(context, c, group);
        case 'visible':
          await g.setVisible(group, !group.visible);
        case 'code':
          if (await confirmDialog(context, title: u['newCode'], body: u['newCodeText'], confirm: u['newCode'], cancel: t.cancel)) {
            await g.newCode(group);
          }
        case 'leave':
          if (await confirmDialog(context,
              title: u['leave'], body: u['leaveText'], confirm: u['leave'], cancel: t.cancel)) {
            await g.leave(group);
          }
      }
    }

    // Equal values share a place; members without numbers get none.
    final places = <int?>[];
    for (var i = 0; i < ranked.length; i++) {
      final value = _value(ranked[i].stats);
      places.add(value == null
          ? null
          : (i > 0 && _value(ranked[i - 1].stats) == value ? places[i - 1] : i + 1));
    }
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      child: Gap(space: 10, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Heading(group.name, size: 19),
              const SizedBox(height: 2),
              Muted([
                fill(group.memberCount == 1 ? u['memberOne'] : u['members'], {'count': group.memberCount}),
                if (group.hiddenCount > 0) fill(u['hiddenCount'], {'count': group.hiddenCount}),
              ].join(' · '), size: 13),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: u['more'],
            onSelected: menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'invite', child: ListTile(leading: const Icon(Icons.person_add_alt), title: Text(u['invite']))),
              PopupMenuItem(
                value: 'visible',
                child: ListTile(
                  leading: Icon(group.visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  title: Text(group.visible ? u['hideMe'] : u['showMe']),
                ),
              ),
              if (group.owner)
                PopupMenuItem(value: 'code', child: ListTile(leading: const Icon(Icons.autorenew), title: Text(u['newCode']))),
              PopupMenuItem(value: 'leave', child: ListTile(leading: const Icon(Icons.logout), title: Text(u['leave']))),
            ],
          ),
        ]),
        if (!group.visible) Notice(text: u['hiddenNotice']),
        if (together > 0)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Notice(
              child: Row(children: [
                Icon(Icons.auto_stories_outlined, size: 18, color: palette.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(fill(u['together'], {'chapters': fmt.number(together), 'week': fmt.number(week)})),
                ),
              ]),
            ),
          ),
        for (final (i, m) in ranked.indexed)
          Builder(builder: (context) {
            final value = _value(m.stats);
            final place = places[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onLongPress: group.owner && !m.me
                  ? () async {
                      if (await confirmDialog(context,
                          title: u['remove'], body: fill(u['removeText'], {'name': m.name}), confirm: u['remove'], cancel: t.cancel)) {
                        await g.remove(group, m);
                      }
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                decoration: BoxDecoration(
                  color: m.me ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      place == null ? '' : '$place',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: place != null && place <= 3 ? palette.primary : palette.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(m.me ? '${m.name} (${u['you']})' : m.name,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (m.owner) ...[
                          const SizedBox(width: 4),
                          Tooltip(message: u['owner'], child: Icon(Icons.star_outline, size: 15, color: palette.ring)),
                        ],
                      ]),
                      Muted(
                        m.stats == null
                            ? u['noStats']
                            : [
                                _lastRead(m.stats!.lastRead),
                                if (m.stats!.streak >= 2) fill(u['valueDays'], {'n': m.stats!.streak}),
                              ].join(' · '),
                        size: 12.5,
                      ),
                    ]),
                  ),
                  Text(_format(value), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            );
          }),
        if (group.owner) Padding(padding: const EdgeInsets.only(right: 10), child: FinePrint(u['ownerHint'])),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showInvite(context, c, group),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: Text(u['invite']),
          ),
        ),
      ]),
    );
  }
}
