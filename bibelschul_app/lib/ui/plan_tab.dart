import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/exports.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import 'bible52_weeks.dart';
import 'day_sheet.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class PlanTab extends StatelessWidget {
  const PlanTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  static const perPage = 14;

  Future<void> _calendar(BuildContext context) async {
    final ok = await shareFile(calendarFile(v.state, c.lang, 'https://leseweg.pages.dev'), 'leseweg-leseplan.ics',
        'text/calendar');
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nativeText(c.lang).shareFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), p = planText(lang), f = bible52Text(lang), e = experienceText(lang), u = ui(lang);
    final fmt = Fmt(lang);
    final s = v.state;
    final palette = context.palette;
    final pages = (v.days.length / perPage).ceil();
    final page = min(c.page, max(0, pages - 1));
    final todayPage = v.dateIndex ~/ perPage;
    return Gap(space: 14, children: [
      Heading(t.plan, size: 26),
      Muted(v.fixed ? 'Bibelleseplan 52' : '${p[s.config.scope ?? 'bible']} · ${p[s.config.order ?? 'canonical']}'),
      Panel(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Gap(space: 10, children: [
          Row(children: [
            Icon(Icons.flag_outlined, color: palette.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${t.target}: ${fmt.date(v.days.last.date, long: true)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (!v.fixed)
              TextButton(
                onPressed: c.busy ? null : () => showDeadlineDialog(context, c),
                child: Text(u['change']),
              ),
          ]),
          Muted(fill(u['coverage'], {
            'done': fmt.number(v.doneCount),
            'total': fmt.number(v.scoped.length),
            'open': fmt.number(v.remainingChapters),
          })),
          if (v.priorIds.isNotEmpty) FinePrint(fill(u['coveragePrevious'], {'count': fmt.number(v.priorIds.length)})),
          Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: () => _calendar(context),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(u['calendar']),
            ),
          ]),
        ]),
      ),
      if (v.fixed) ...[
        Muted(u['b52Explain']),
        Panel(
          child: Bible52Weeks(
            value: v.doneSet.keys.toList(),
            lang: lang,
            current: v.dateIndex,
            onChoose: c.choose,
          ),
        ),
      ] else ...[
        Muted(u['planSub']),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final d in v.days.skip(page * perPage).take(perPage))
              _row(context, d.index, d.date, d.chapters.isEmpty, d.words, v.readLabel(d.chapters),
                  v.planState.adaptive?.finished.contains(d.index) ?? false),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.outlined(
            tooltip: t.previous,
            onPressed: page == 0 ? null : () => c.update(() => c.page = page - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${t.page} ${page + 1} / $pages', style: TextStyle(color: palette.foreground)),
          ),
          IconButton.outlined(
            tooltip: t.next,
            onPressed: (page + 1) * perPage >= v.days.length ? null : () => c.update(() => c.page = page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
          if (page != todayPage && v.dateIndex < v.days.length) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: () => c.update(() => c.page = todayPage), child: Text(u['jumpToday'])),
          ],
        ]),
      ],
      Details(summary: t.explain, children: [
        Text(v.fixed ? f.fixed : u['howPlan']),
        Text(e.approxWeights),
        const FinePrint('Luther 1912 · Public Domain · bible-data (github.com/midvash/bible-data)'),
      ]),
    ]);
  }

  Widget _row(BuildContext context, int index, String date, bool empty, int words, String label, bool isDone) {
    final lang = c.lang;
    final t = text(lang), u = ui(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final isToday = date == v.currentDate;
    final past = date.compareTo(v.currentDate) < 0;
    return Material(
      color: isToday ? palette.accent : Colors.transparent,
      child: InkWell(
        onTap: () => showDaySheet(context, c, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: isDone ? palette.primary : palette.muted,
              foregroundColor: isDone ? palette.onPrimary : palette.foreground,
              child: isDone ? const Icon(Icons.check, size: 18) : Text('${index + 1}', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  past && empty ? t.noReadingLogged : label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: past && !isDone ? palette.mutedForeground : palette.foreground),
                ),
                Muted('${fmt.weekday(date)}, ${fmt.date(date)}${isToday ? ' · ${u['todayLabel']}' : ''}', size: 12.5),
              ]),
            ),
            const SizedBox(width: 8),
            Text(words > 0 && !past ? fmt.time(v.pace.secondsPerWord * words) : '',
                style: TextStyle(fontWeight: FontWeight.w600, color: palette.mutedForeground, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}
