import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/exports.dart';
import '../core/reading_time.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), p = planText(lang), e = experienceText(lang), time = readingTimeText(lang);
    final fmt = Fmt(lang);
    final s = v.state;
    final palette = context.palette;
    final stats = [
      (p.measured, fmt.time(v.totalSeconds), '', Icons.schedule),
      (t.avgTime, v.timedSessions.isEmpty ? '–' : fmt.time(v.averageSession), '', Icons.bar_chart),
      (t.units, '${v.sessions.length}', '', Icons.check_circle_outline),
      (t.chapters, '${v.doneCount}', '/ ${fmt.number(v.scoped.length)}', Icons.menu_book_outlined),
    ];
    final chartDates = [for (var i = 0; i < 7; i++) addDays(v.currentDate, i - 6)];
    final maxValue = max(60, chartDates.map((d) => v.chartValues[d] ?? 0).reduce(max));
    return Gap(space: 14, children: [
      Eyebrow(t.measured),
      Heading(t.stats, size: 26),
      Muted(t.statsSub),
      if (s.sessions == null || v.sessions.any((x) => x.id.startsWith('legacy-'))) FinePrint(e.legacySessions),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
        children: [
          for (final (label, value, unit, icon) in stats)
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: palette.ring),
                const Spacer(),
                Muted(label, size: 13),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    if (unit.isNotEmpty) TextSpan(text: ' $unit', style: const TextStyle(fontSize: 13)),
                  ])),
                ),
              ]),
            ),
        ],
      ),
      ReadingTimeOverview(summary: v.timeSummary, lang: lang),
      Panel(
        child: Gap(children: [
          Row(children: [
            Icon(Icons.schedule, color: palette.ring),
            const SizedBox(width: 8),
            Expanded(child: Heading(t.paceTitle, size: 19)),
          ]),
          Text(v.pace.personal ? t.personalEstimate : (v.pace.learning ? e.learning : t.defaultEstimate),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Muted(v.pace.personal || v.pace.learning
              ? t.paceBased.replaceFirst('{chapters}', '${v.pace.chapters}').replaceFirst('{time}', fmt.time(v.pace.seconds))
              : t.paceFallback),
          Muted(e.paceHelp),
          if (v.pace.excluded > 0) Notice(text: '${e.excluded}: ${v.pace.excluded}'),
          Details(summary: e.advanced, children: [
            for (final (index, sample) in (s.pace?.samples ?? []).indexed)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${v.fixed ? bible52Position(sample.day, lang) : fmt.date(addDays(s.config.start, sample.day))} · '
                    '${sample.chapters.length} ${t.chapters} · ${fmt.time(sample.seconds)}'),
                const SizedBox(height: 6),
                LabeledDropdown<String>(
                  label: e.paceUse,
                  value: sample.review ?? 'auto',
                  enabled: !c.busy,
                  items: [('auto', e.automatic), ('confirmed', e.confirmed), ('excluded', e.excludedChoice)],
                  onChanged: (review) => c.mutate(
                      {'action': 'review-pace', 'index': index, 'seconds': sample.seconds, 'review': review}),
                ),
              ]),
          ]),
        ]),
      ),
      Panel(
        child: Gap(children: [
          Heading(t.chartTitle, size: 19),
          Muted('${t.measured} · ${time.chart}'),
          SizedBox(
            height: 170,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final date in chartDates)
                Expanded(
                  child: Semantics(
                    label: '${fmt.date(date)} · ${fmt.time(v.chartValues[date] ?? 0)}',
                    child: Tooltip(
                      message: '${fmt.date(date)} · ${fmt.time(v.chartValues[date] ?? 0)}',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(readingTimeClock(v.chartValues[date] ?? 0),
                            style: TextStyle(fontSize: 11, color: palette.mutedForeground)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Container(
                            width: 22,
                            alignment: Alignment.bottomCenter,
                            decoration: BoxDecoration(color: palette.muted, borderRadius: BorderRadius.circular(6)),
                            child: FractionallySizedBox(
                              heightFactor: max((v.chartValues[date] ?? 0) > 0 ? 0.03 : 0.0,
                                  (v.chartValues[date] ?? 0) / maxValue),
                              child: Container(
                                decoration:
                                    BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(fmt.weekday(date), style: TextStyle(fontSize: 11, color: palette.mutedForeground)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          if (s.logs.isEmpty && s.timer == null) Muted(t.noTimer),
        ]),
      ),
      Panel(
        child: Gap(children: [
          Heading(t.recent, size: 19),
          if (v.timedSessions.isEmpty)
            Muted(t.noData)
          else
            for (final d in v.timedSessions.reversed.take(10))
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => c.choose(d.day),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            d.chapters.isNotEmpty
                                ? v.readLabel([for (final id in d.chapters) v.inventory[id]])
                                : t.noReadingLogged,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted(
                            '${v.fixed ? bible52Position(d.day, lang) : '${t.day} ${d.day + 1}'} · ${fmt.date(d.date)}',
                            size: 12.5),
                      ]),
                    ),
                    Text(fmt.time(d.seconds), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await shareFile(csvFile(s, lang), 'leseweg-statistik.csv', 'text/csv');
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nativeText(lang).shareFailed)));
              }
            },
            icon: const Icon(Icons.ios_share, size: 17),
            label: Text(nativeText(lang).exportCsv),
          ),
        ]),
      ),
    ]);
  }
}
