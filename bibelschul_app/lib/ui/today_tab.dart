import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/editions.dart';
import '../core/planner.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'dialogs.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  Future<void> openFinish(BuildContext context) async {
    if (v.running && await c.mutate({'action': 'timer', 'mode': 'pause', 'day': v.day.index}) == null) return;
    if (context.mounted) await showFinishDialog(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), f = bible52Text(lang), p = planText(lang);
    final deadline = deadlineText(lang);
    final fmt = Fmt(lang);
    final s = v.state, day = v.day;
    final palette = context.palette;
    final busy = c.busy;

    final heading = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Gap(space: 6, children: [
          Eyebrow(fmt.date(v.currentDate, long: true)),
          Heading(v.doneCount == v.scoped.length ? t.completePlan : t.welcome, size: 26),
          Muted('${editionName(s.config.edition)} · ${v.fixed ? 'Bibelleseplan 52' : p[s.config.scope ?? 'bible']}'),
        ]),
      ),
    ]);
    final goal = v.fixed
        ? Chip(avatar: const Icon(Icons.calendar_month_outlined, size: 16), label: Text(f.description))
        : ActionChip(
            avatar: const Icon(Icons.calendar_month_outlined, size: 16),
            label: Text('${t.target} · ${fmt.date(v.days.last.date, long: true)}'),
            tooltip: '${deadline.edit}: ${fmt.date(v.days.last.date, long: true)}',
            onPressed: busy ? null : () => showDeadlineDialog(context, c),
          );

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
              Text(
                v.running ? t.timerRunning : (v.canRead && !v.dayDone ? t.timerPaused : e.dailyMeasured),
                style: TextStyle(color: v.running ? palette.onPrimary : palette.mutedForeground),
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

    final readingCard = Panel(
      child: Gap(children: [
        Row(children: [
          Expanded(
            child: Eyebrow(v.fixed
                ? 'Bibelleseplan 52'
                : (v.dayDone || day.date.compareTo(v.currentDate) < 0 ? t.read : t.recommended)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(20)),
            child: Text(v.fixed ? bible52Position(day.index, lang) : '${t.day} ${day.index + 1} / ${v.days.length}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.foreground)),
          ),
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
          _meta(context, Icons.calendar_today_outlined, v.fixed ? f.original : fmt.date(day.date)),
          if (day.words > 0)
            _meta(
                context,
                Icons.schedule,
                '${t.approx} ${fmt.time(v.pace.secondsPerWord * day.words)} · '
                '${v.pace.personal ? t.personalEstimate : (v.pace.learning ? e.learning : t.defaultEstimate)}'),
        ]),
        ReadingContext(config: s.config, items: v.sessionItems, lang: lang),
        Muted(v.fixed
            ? (v.dayDone ? f.saved : f.finish)
            : (v.dayDone ? t.sessionSaved : (v.canRead ? t.adaptiveHint : t.previewHint))),
        if (v.sessionItems.isNotEmpty || v.canRead) ...[
          ?timerBox,
          if (s.timer != null && !v.running)
            TextButton.icon(
              onPressed: () => c.choose(s.timer?.day ?? s.pace?.draft?.day ?? v.dateIndex),
              icon: const Icon(Icons.schedule, size: 16),
              label: Text(t.goTimer),
            ),
          if (v.seconds > 14400) Notice(text: t.longTimer, kind: NoticeKind.warning),
          Column(children: [
            for (final ch in v.sessionItems)
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
                      : (x) => c.mutate({'action': 'chapter', 'chapter': ch.id, 'done': x == true}),
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
                  secondary: Muted('${t.approx} ${fmt.time(v.pace.secondsPerWord * ch.words)}', size: 12.5),
                ),
              ),
          ]),
          if (v.canRead && !v.dayDone) ...[
            if (v.nextExtra != null)
              OutlinedButton.icon(
                onPressed: busy ? null : () => c.mutate({'action': 'extend', 'day': day.index}),
                icon: const Icon(Icons.add, size: 18),
                label: Text('${t.addChapter} · ${v.readLabel([v.nextExtra!])}', overflow: TextOverflow.ellipsis),
              ),
            Muted('${v.sessionItems.where((ch) => v.doneSet.containsKey(ch.id)).length} ${t.chaptersChecked}'),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || (s.timer != null && !v.running) ? null : () => openFinish(context),
                icon: const Icon(Icons.check),
                label: Text(e.finish),
              ),
            ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ||
                      (v.fixed && (!v.canRead || v.sessionItems.every((ch) => v.priorIds.contains(ch.id))))
                  ? null
                  : () => showTimeCorrectionDialog(context, c, day.index, v.seconds),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: Text(t.editTime),
            ),
          ),
        ],
      ]),
    );

    final progress = Panel(
      child: Gap(children: [
        Row(children: [
          Expanded(child: Heading(t.progress, size: 17)),
          Icon(Icons.menu_book_outlined, color: palette.mutedForeground),
        ]),
        Text.rich(TextSpan(children: [
          TextSpan(text: formattedPercent(v.percent, lang), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
          const TextSpan(text: ' %', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ])),
        Semantics(
          label: t.progress,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v.percent / 100, minHeight: 10),
          ),
        ),
        Muted('${fmt.number(v.doneCount)} / ${fmt.number(v.scoped.length)} ${t.chapters} · ${t.byText}'),
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
            onTap: () => c.choose(d.index),
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
                    Muted(d.words > 0 ? '${t.approx} ${fmt.time(v.pace.secondsPerWord * d.words)}' : t.rest, size: 12.5),
                  ]),
                ),
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
      Align(alignment: Alignment.centerLeft, child: goal),
      if (!v.fixed && v.days.first.date.compareTo(v.currentDate) > 0)
        Notice(text: '${t.future} ${fmt.date(v.days.first.date, long: true)}.'),
      if (!v.fixed && v.remainingChapters > 0 && v.currentDate.compareTo(v.days.last.date) > 0)
        Notice(text: t.deadlinePassed, kind: NoticeKind.warning),
      if (v.planState.adaptive?.unplanned?.isNotEmpty ?? false)
        Notice(
            kind: NoticeKind.warning,
            text: fill(p.unscheduled, {'count': v.planState.adaptive!.unplanned!.length})),
      if (!v.canRead)
        Notice(
          text: v.fixed ? f.open : (day.date.compareTo(v.currentDate) < 0 ? t.historyHint : t.previewHint),
          actions: [
            OutlinedButton(onPressed: () => c.choose(v.dateIndex), child: Text(v.fixed ? f.resume : t.backToday)),
          ],
        ),
      readingCard,
      progress,
      next,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.menu_book_outlined, size: 18, color: palette.mutedForeground),
        const SizedBox(width: 8),
        Expanded(child: Muted(t.timerNote, size: 13)),
      ]),
    ]);
  }

  Widget _meta(BuildContext context, IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.palette.mutedForeground),
        const SizedBox(width: 5),
        Flexible(child: Muted(label, size: 13)),
      ]);
}
