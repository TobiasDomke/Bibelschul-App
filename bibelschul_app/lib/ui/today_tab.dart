import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/editions.dart';
import '../core/insights.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/util.dart';
import '../i18n/feature_texts.dart';
import '../i18n/i18n.dart';
import 'dialogs.dart';
import 'notes_ui.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  /// Finishing takes one tap. Only an unusual measurement asks first whether it
  /// should train the reading-time forecast.
  Future<void> _finish(BuildContext context, {bool all = false}) async {
    String? paceChoice;
    if (v.unusual) {
      final f = featureText(c.lang), e = experienceText(c.lang);
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(f['confirmPaceTitle']),
          content: Text(e.outlier),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(f['skipPace'])),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(f['usePace'])),
          ],
        ),
      );
      if (use == null) return;
      paceChoice = use ? 'confirmed' : 'excluded';
    }
    if (all) {
      await c.readAll(v.day.index, [for (final ch in v.sessionItems) ch.id], paceChoice: paceChoice);
    } else {
      await c.finish(v.day.index, paceChoice: paceChoice);
    }
  }

  void _howItWorks(BuildContext context) {
    final t = text(c.lang), f = featureText(c.lang), b = bible52Text(c.lang);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Gap(children: [
            Heading(f['howItWorks'], size: 19),
            Text(v.fixed ? b.finish : t.adaptiveHint),
            Text(t.timerNote),
            Text(t.finishExplanation),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), f = bible52Text(lang), p = planText(lang);
    final x = featureText(lang);
    final deadline = deadlineText(lang);
    final fmt = Fmt(lang);
    final s = v.state, day = v.day;
    final palette = context.palette;
    final busy = c.busy;
    final groupName = c.prefs.groupName(s.id);

    final heading = Gap(space: 6, children: [
      Eyebrow(fmt.date(v.currentDate, long: true)),
      Heading(v.doneCount == v.scoped.length ? t.completePlan : t.welcome, size: 26),
      Muted([
        if (groupName.isNotEmpty) '${x['sharedPlan']}: $groupName',
        editionName(s.config.edition),
        v.fixed ? 'Bibelleseplan 52' : p[s.config.scope ?? 'bible'],
      ].join(' · ')),
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
          child: ListTile(leading: const Icon(Icons.info_outline), title: Text(x['howItWorks'])),
        ),
      ],
    );

    final unchecked = v.sessionItems.where((ch) => !v.doneSet.containsKey(ch.id)).toList();
    final genre = v.sessionItems.isNotEmpty ? genreOfBook(v.sessionItems.first.bookIndex) : null;
    final note = c.noteFor(day.index);
    final readSomething = v.sessionItems.any((ch) => v.doneSet.containsKey(ch.id)) || v.dayDone;

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
          _meta(context, Icons.calendar_today_outlined, v.fixed ? f.original : fmt.date(day.date)),
          if (day.words > 0)
            _meta(
                context,
                Icons.schedule,
                '${t.approx} ${fmt.time(estimatedSeconds(day.words, v.pace))} · '
                '${v.pace.personal ? t.personalEstimate : (v.pace.learning ? e.learning : t.defaultEstimate)}'),
        ]),
        ReadingContext(config: s.config, items: v.sessionItems, lang: lang),
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
                  secondary: Muted('${t.approx} ${fmt.time(estimatedSeconds(ch.words, v.pace))}', size: 12.5),
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
            Row(children: [
              if (unchecked.isNotEmpty) ...[
                Expanded(
                  child: Tooltip(
                    message: x['readAllHelp'],
                    child: OutlinedButton.icon(
                      onPressed: busy || (s.timer != null && !v.running) ? null : () => _finish(context, all: true),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(x['readAll']),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || (s.timer != null && !v.running) ? null : () => _finish(context),
                  icon: const Icon(Icons.check),
                  label: Text(e.finish),
                ),
              ),
            ]),
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
        if (genre != null && (v.canRead || readSomething))
          Details(summary: x['questions'], children: [
            for (final q in x.questions[genre]!)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(Icons.chat_bubble_outline, size: 16, color: palette.ring),
                ),
                Expanded(child: Text(q)),
              ]),
          ]),
        if (readSomething || note != null)
          NotePreview(
            c: c,
            note: note,
            onEdit: () => showNoteEditor(context, c,
                day: day.index,
                date: v.dayDone || day.date.compareTo(v.currentDate) < 0 ? day.date : v.currentDate,
                passage: v.fixed ? bible52Units[day.index].label : v.readLabel(v.sessionItems)),
          ),
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
                    Muted(d.words > 0 ? '${t.approx} ${fmt.time(estimatedSeconds(d.words, v.pace))}' : t.rest,
                        size: 12.5),
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
      Align(alignment: Alignment.centerLeft, child: goal),
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
              'time': fmt.time(v.remainingDays > 0
                  ? estimatedSeconds(v.remainingWords / (v.remainingDays + 1), v.pace)
                  : estimatedSeconds(v.remainingWords, v.pace)),
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
      next,
    ]);
  }

  Widget _meta(BuildContext context, IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.palette.mutedForeground),
        const SizedBox(width: 5),
        Flexible(child: Muted(label, size: 13)),
      ]);
}
