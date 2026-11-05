import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../app/reading_stats.dart';
import '../core/editions.dart';
import '../core/insights.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/feature_texts.dart';
import '../i18n/i18n.dart';
import 'day_sheet.dart';
import 'dialogs.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  /// Finishing takes one tap. Only a clearly unusual measurement asks whether
  /// it should count for the reading speed – in plain words, with the numbers.
  Future<void> _finish(BuildContext context, {bool all = false}) async {
    String? paceChoice;
    if (v.unusual) {
      final u = ui(c.lang), t = text(c.lang);
      final fmt = Fmt(c.lang);
      final sample = v.pendingSample!;
      final ids = {...sample.chapters, if (all) ...v.sessionItems.map((ch) => ch.id)};
      final chapters = [for (final ch in v.sessionItems) if (ids.contains(ch.id)) ch];
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(u['unusualTitle']),
          content: Text(fill(u['unusualText'], {
            'measured': fmt.time(sample.seconds),
            'passage': chapters.isEmpty ? t.rest : v.readLabel(chapters),
            'expected': fmt.time(chaptersSeconds(chapters, v.pace)),
          })),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(u['unusualNo'])),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(u['unusualYes'])),
          ],
        ),
      );
      if (use == null) return;
      paceChoice = use ? 'confirmed' : 'excluded';
    }
    if (all) {
      await c.readAll(v.day.index, [for (final ch in v.sessionItems) ch.id], paceChoice: paceChoice);
    } else {
      await c.finish(v.day.index,
          paceChoice: paceChoice, moved: [for (final ch in v.ordered(v.sessionItems)) if (!v.doneSet.containsKey(ch.id)) ch]);
    }
  }

  void _howItWorks(BuildContext context) {
    final u = ui(c.lang), b = bible52Text(c.lang);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Gap(children: [
            Heading(u['howItWorks'], size: 19),
            Text(v.fixed ? b.finish : u['howCheck']),
            Text(u['howTimer']),
            if (!v.fixed) Text(u['howPlan']),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), f = bible52Text(lang), p = planText(lang);
    final u = ui(lang);
    final x = featureText(lang);
    final deadline = deadlineText(lang);
    final fmt = Fmt(lang);
    final s = v.state, day = v.day;
    final palette = context.palette;
    final busy = c.busy;
    final groupName = c.prefs.groupName(s.id);
    final otherDay = !v.fixed && day.index != v.dateIndex;
    final streak = readingStreak(s, v.currentDate);
    final items = v.ordered(v.sessionItems);

    final heading = Gap(space: 6, children: [
      Eyebrow(fmt.date(otherDay ? day.date : v.currentDate, long: true)),
      Heading(
        v.doneCount == v.scoped.length
            ? t.completePlan
            : (v.dayDone && !otherDay ? u['doneToday'] : t.welcome),
        size: 26,
      ),
      Muted([
        if (groupName.isNotEmpty) '${x['sharedPlan']}: $groupName',
        editionName(s.config.edition),
        v.fixed ? 'Bibelleseplan 52' : planText(lang)[s.config.scope ?? 'bible'],
      ].join(' · ')),
    ]);

    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      if (v.fixed)
        Chip(avatar: const Icon(Icons.calendar_month_outlined, size: 16), label: Text(f.description))
      else
        ActionChip(
          avatar: const Icon(Icons.flag_outlined, size: 16),
          label: Text('${t.target} · ${fmt.date(v.days.last.date, long: true)}'),
          tooltip: deadline.edit,
          onPressed: busy ? null : () => showDeadlineDialog(context, c),
        ),
      if (streak >= 2)
        Chip(
          avatar: Icon(Icons.local_fire_department_outlined, size: 16, color: palette.primary),
          label: Text(fill(u['streakDays'], {'days': streak})),
        ),
    ]);

    final timerBox = (v.canRead || v.seconds > 0)
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: v.running ? palette.primary : palette.muted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Semantics(
                label: t.measured,
                child: Text(
                  clockText(v.sessionSeconds),
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: v.running ? palette.onPrimary : palette.foreground,
                  ),
                ),
              ),
              // Same height in every state, so the chapters below never jump.
              SizedBox(
                height: 20,
                child: Text(
                  v.running ? u['timerRunning'] : (v.canRead && !v.dayDone ? u['timerIdle'] : e.dailyMeasured),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: v.running ? palette.onPrimary : palette.mutedForeground),
                ),
              ),
              if (v.canRead && !v.dayDone) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: v.running
                      ? FilledButton.styleFrom(backgroundColor: palette.onPrimary, foregroundColor: palette.primary)
                      : null,
                  onPressed: busy || (s.timer != null && !v.running)
                      ? null
                      : () => c.mutate({'action': 'timer', 'mode': v.running ? 'pause' : 'start', 'day': day.index}),
                  icon: Icon(v.running ? Icons.pause : Icons.play_arrow),
                  label: Text(v.running ? t.pause : (v.sessionSeconds > 0 ? t.resume : t.startTimer)),
                ),
              ],
            ]),
          )
        : null;

    final canCorrect = !busy && !(v.fixed && (!v.canRead || v.sessionItems.every((ch) => v.priorIds.contains(ch.id))));
    final menu = PopupMenuButton<String>(
      tooltip: x['more'],
      icon: Icon(Icons.more_horiz, color: palette.mutedForeground),
      onSelected: (value) => switch (value) {
        'time' => showTimeCorrectionDialog(context, c, day.index, v.seconds),
        _ => _howItWorks(context),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'time',
          enabled: canCorrect,
          child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t.editTime)),
        ),
        PopupMenuItem(
          value: 'info',
          child: ListTile(leading: const Icon(Icons.info_outline), title: Text(u['howItWorks'])),
        ),
      ],
    );

    final unchecked = items.where((ch) => !v.doneSet.containsKey(ch.id)).toList();
    final checked = items.length - unchecked.length;
    final timerLocked = s.timer != null && !v.running;

    final readingCard = Panel(
      child: Gap(children: [
        Row(children: [
          Expanded(
            child: Eyebrow(v.fixed
                ? 'Bibelleseplan 52'
                : (v.dayDone || day.date.compareTo(v.currentDate) < 0 ? t.read : u['todayReading'])),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(20)),
            child: Text(v.fixed ? bible52Position(day.index, lang) : '${t.day} ${day.index + 1} / ${v.days.length}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.foreground)),
          ),
          menu,
        ]),
        Heading(
          v.fixed
              ? bible52Units[day.index].label
              : (day.date.compareTo(v.currentDate) < 0 && day.chapters.isEmpty
                  ? t.noReadingLogged
                  : v.readLabel(day.chapters)),
          size: 24,
        ),
        Wrap(spacing: 14, runSpacing: 6, children: [
          if (v.fixed) _meta(context, Icons.category_outlined, u['cat${day.index % 7}']),
          if (day.words > 0)
            _meta(
                context,
                Icons.schedule,
                '${t.approx} ${fmt.time(chaptersSeconds(day.chapters, v.pace))}'
                '${v.pace.personal ? ' · ${u['yourPace']}' : ''}'),
        ]),
        ReadingContext(config: s.config, items: v.sessionItems, lang: lang),
        if (v.sessionItems.isNotEmpty || v.canRead) ...[
          ?timerBox,
          if (timerLocked)
            TextButton.icon(
              onPressed: () => c.choose(s.timer?.day ?? s.pace?.draft?.day ?? v.dateIndex),
              icon: const Icon(Icons.schedule, size: 16),
              label: Text(t.goTimer),
            ),
          if (v.seconds > 14400) Notice(text: t.longTimer, kind: NoticeKind.warning),
          Column(children: [
            for (final ch in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CheckboxListTile(
                  tileColor: v.doneSet.containsKey(ch.id) ? palette.accent : palette.card,
                  controlAffinity: ListTileControlAffinity.leading,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), side: BorderSide(color: palette.border)),
                  value: v.doneSet.containsKey(ch.id),
                  onChanged: busy || !v.canRead || (v.fixed ? v.priorIds.contains(ch.id) : v.dayDone)
                      ? null
                      : (value) => c.mutate({'action': 'chapter', 'chapter': ch.id, 'done': value == true}),
                  title: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: v.readLabel([ch]),
                      style: TextStyle(
                        decoration: v.doneSet.containsKey(ch.id) ? TextDecoration.lineThrough : null,
                        color: palette.foreground,
                      ),
                    ),
                    if (v.extraIds.contains(ch.id))
                      TextSpan(text: '  ${t.additional}', style: TextStyle(fontSize: 12, color: palette.ring)),
                  ])),
                  secondary: Muted('${t.approx} ${fmt.time(chaptersSeconds([ch], v.pace))}', size: 12.5),
                ),
              ),
          ]),
          if (v.canRead && !v.dayDone) ...[
            if (v.nextExtra != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: busy ? null : () => c.mutate({'action': 'extend', 'day': day.index}),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(fill(u['addNext'], {'passage': v.readLabel([v.nextExtra!])})),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || timerLocked ? null : () => _finish(context, all: unchecked.isNotEmpty),
                icon: Icon(unchecked.isEmpty ? Icons.check : Icons.done_all),
                label: Text(unchecked.isEmpty ? u['finish'] : u['finishAll']),
              ),
            ),
            if (unchecked.isNotEmpty && (checked > 0 || v.sessionSeconds > 0))
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy || timerLocked ? null : () => _finish(context),
                  child: Text(checked > 0 ? fill(u['finishChecked'], {'count': checked}) : u['finishTimeOnly']),
                ),
              ),
            if (unchecked.isNotEmpty && (checked > 0 || v.sessionSeconds > 0)) FinePrint(u['finishCheckedHelp']),
          ],
          if (v.dayDone)
            Row(children: [
              Icon(Icons.check_circle, color: palette.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(t.sessionSaved, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          if (v.canRead && v.dayDone && v.remainingChapters > 0)
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => v.fixed ? c.choose(v.dateIndex) : c.mutate({'action': 'reopen', 'day': day.index}),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(v.fixed ? f.next : t.continueReading),
            ),
        ],
      ]),
    );

    final progress = Panel(
      child: Gap(children: [
        Row(children: [
          Expanded(child: Heading(t.progress, size: 17)),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: formattedPercent(v.percentExact, lang),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.foreground)),
            TextSpan(text: ' %', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.foreground)),
          ])),
        ]),
        Semantics(
          label: t.progress,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v.percent / 100, minHeight: 10),
          ),
        ),
        Muted('${fill(u['chaptersOf'], {'done': fmt.number(v.doneCount), 'total': fmt.number(v.scoped.length)})} · ${u['byWords']}'),
        if (v.totalSeconds > 0)
          Row(children: [
            Icon(Icons.schedule, size: 19, color: palette.mutedForeground),
            const SizedBox(width: 8),
            Expanded(child: Text(p.measured)),
            Text(fmt.time(v.totalSeconds), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
      ]),
    );

    final upcoming = v.days
        .where((d) => d.index > day.index && (!v.fixed || !(v.planState.adaptive?.finished.contains(d.index) ?? false)))
        .take(3);
    final next = Panel(
      child: Gap(children: [
        Eyebrow(t.upcoming),
        for (final d in upcoming)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showDaySheet(context, c, d.index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                DateSquare(
                  top: v.fixed ? '${d.index ~/ 7 + 1}' : '${dateAt(d.date).day}',
                  bottom: v.fixed ? f.week : fmt.month(d.date),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      d.date.compareTo(v.currentDate) < 0 && d.chapters.isEmpty ? t.noReadingLogged : v.readLabel(d.chapters),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(d.words > 0 ? '${t.approx} ${fmt.time(chaptersSeconds(d.chapters, v.pace))}' : t.rest,
                        size: 12.5),
                  ]),
                ),
                Icon(Icons.chevron_right, color: palette.mutedForeground),
              ]),
            ),
          ),
        TextButton(
          onPressed: () => c.update(() {
            c.tab = 'plan';
            c.page = day.index ~/ 14;
          }),
          child: Text(t.viewPlan),
        ),
      ]),
    );

    final behind = c.prefs.behindHiddenUntil(s.id).compareTo(v.currentDate) >= 0
        ? null
        : behindSchedule(s, v.currentDate);

    return Gap(space: 14, children: [
      if (s.config.edition == null && lang.name != 'de')
        Notice(text: e.legacyEdition, actions: [OutlinedButton(onPressed: () => c.setTab('settings'), child: Text(t.settings))]),
      if (v.backupDue)
        Notice(text: e.backupReminder, actions: [
          OutlinedButton(onPressed: () => c.setTab('settings'), child: Text(e.backupGo)),
          TextButton(
            onPressed: () async {
              await c.prefs.recordBackup(s.id, 'snoozed');
              c.update(() {});
            },
            child: Text(e.backupLater),
          ),
        ]),
      if (s.editionReview?.isNotEmpty ?? false)
        Notice(
            kind: NoticeKind.warning,
            text: e.reviewEdition,
            actions: [OutlinedButton(onPressed: () => c.setTab('settings'), child: Text(t.settings))]),
      heading,
      chips,
      if (!v.fixed && v.days.first.date.compareTo(v.currentDate) > 0)
        Notice(text: '${t.future} ${fmt.date(v.days.first.date, long: true)}.'),
      if (!v.fixed && v.remainingChapters > 0 && v.currentDate.compareTo(v.days.last.date) > 0)
        Notice(text: t.deadlinePassed, kind: NoticeKind.warning),
      if (v.planState.adaptive?.unplanned?.isNotEmpty ?? false)
        Notice(
            kind: NoticeKind.warning,
            text: fill(p.unscheduled, {'count': v.planState.adaptive!.unplanned!.length})),
      if (behind != null && v.canRead && s.timer == null)
        Notice(
          kind: NoticeKind.warning,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fill(x['behind'], {'chapters': behind.chapters}), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(fill(x['behindHelp'], {
              'time': fmt.time(v.remainingDays > 0 ? v.remainingSeconds / (v.remainingDays + 1) : v.remainingSeconds),
            })),
          ]),
          actions: [
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final end = addDays(v.days.last.date, behind.days);
                      final updated = await c.mutate({'action': 'deadline', 'end': end});
                      if (updated != null) c.update(() => c.message = 'deadline');
                    },
              child: Text(fill(x['behindExtend'], {'days': behind.days})),
            ),
            TextButton(
              onPressed: () {
                c.prefs.hideBehind(s.id, addDays(v.currentDate, 6));
                c.update(() {});
              },
              child: Text(x['behindKeep']),
            ),
          ],
        ),
      if (!v.canRead)
        Notice(
          text: v.fixed ? f.open : (day.date.compareTo(v.currentDate) < 0 ? t.historyHint : t.previewHint),
          actions: [
            OutlinedButton(onPressed: () => c.choose(v.dateIndex), child: Text(v.fixed ? f.resume : t.backToday)),
          ],
        ),
      readingCard,
      progress,
      if (upcoming.isNotEmpty) next,
    ]);
  }

  Widget _meta(BuildContext context, IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.palette.mutedForeground),
        const SizedBox(width: 5),
        Flexible(child: Muted(label, size: 13)),
      ]);
}
