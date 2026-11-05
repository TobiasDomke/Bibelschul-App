import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'bible52_weeks.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class PlanTab extends StatelessWidget {
  const PlanTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), p = planText(lang), f = bible52Text(lang), e = experienceText(lang);
    final fmt = Fmt(lang);
    final s = v.state;
    final palette = context.palette;
    final pages = (v.days.length / 14).ceil();
    final page = min(c.page, max(0, pages - 1));
    return Gap(space: 14, children: [
      if (v.fixed)
        Eyebrow('${t.target}: ${fmt.date(v.days.last.date, long: true)}')
      else
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: c.busy ? null : () => showDeadlineDialog(context, c),
          icon: const Icon(Icons.edit_outlined, size: 15),
          label: Text('${t.target}: ${fmt.date(v.days.last.date, long: true)}'),
        ),
      Heading(t.plan, size: 26),
      Muted(v.fixed ? 'Bibelleseplan 52' : '${p[s.config.scope ?? 'bible']} · ${p[s.config.order ?? 'canonical']}'),
      Muted(v.fixed ? f.fixed : t.planSub),
      FinePrint(fill(p.coverage, {
        'total': v.scoped.length,
        'previous': v.priorIds.length,
        'completed': s.done.length,
        'remaining': v.remainingChapters,
      })),
      if (v.fixed)
        Panel(
          child: Bible52Weeks(
            value: v.doneSet.keys.toList(),
            lang: lang,
            current: v.dateIndex,
            onChoose: c.choose,
          ),
        )
      else ...[
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final d in v.days.skip(page * 14).take(14))
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${t.page} ${page + 1} / $pages', style: TextStyle(color: palette.foreground)),
          ),
          IconButton.outlined(
            tooltip: t.next,
            onPressed: (page + 1) * 14 >= v.days.length ? null : () => c.update(() => c.page = page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
      ],
      Details(summary: t.explain, children: [
        Text(e.approxWeights),
        const FinePrint('Luther 1912 · Public Domain · bible-data (github.com/midvash/bible-data)'),
      ]),
    ]);
  }

  Widget _row(BuildContext context, int index, String date, bool empty, int words, String label, bool isDone) {
    final lang = c.lang;
    final t = text(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final isToday = date == v.currentDate;
    return Material(
      color: isToday ? palette.accent : Colors.transparent,
      child: InkWell(
        onTap: () => c.choose(index),
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
                  date.compareTo(v.currentDate) < 0 && empty ? t.noReadingLogged : label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: palette.foreground),
                ),
                Muted('${fmt.date(date, long: true)}${isToday ? ' · ${t.today}' : ''}', size: 12.5),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(words > 0 ? fmt.time(v.pace.secondsPerWord * words) : '–',
                  style: TextStyle(fontWeight: FontWeight.w600, color: palette.foreground)),
              Muted(isDone ? t.finished : (date.compareTo(v.currentDate) < 0 ? t.read : t.recommended), size: 12),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Used by the today tab's "date square" for the 52-week plan.
int weekOf(int index) => index ~/ 7 + 1;

String isoToday(String zone) => today(zone);
