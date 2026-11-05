import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/reading_time.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import '../core/data.g.dart';
import '../core/insights.dart';
import '../app/reading_stats.dart';
import '../i18n/app_texts.dart';
import '../i18n/feature_texts.dart';
import 'groups_view.dart';
import 'share_card.dart';
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
    final t = text(lang), e = experienceText(lang), time = readingTimeText(lang);
    final fmt = Fmt(lang);
    final s = v.state;
    final palette = context.palette;
    final u = ui(lang);
    final streak = readingStreak(s, v.currentDate);
    final wpm = wordsPerMinute(v.pace);
    final stats = [
      (u['statChapters'], fmt.number(v.doneCount), '/ ${fmt.number(v.scoped.length)}', Icons.menu_book_outlined),
      (u['statStreak'], streak == 0 ? '–' : fill(streak == 1 ? u['valueDay'] : u['valueDays'], {'n': streak}), '',
          Icons.local_fire_department_outlined),
      (u['statTime'], v.totalSeconds == 0 ? '–' : fmt.time(v.totalSeconds), '', Icons.schedule),
      (u['statSpeed'], wpm == null ? '–' : fill(u['valueSpeed'], {'n': wpm}), '', Icons.speed),
    ];
    final chartDates = [for (var i = 0; i < 7; i++) addDays(v.currentDate, i - 6)];
    final maxValue = max(60, chartDates.map((d) => v.chartValues[d] ?? 0).reduce(max));
    final switcher = SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'me', icon: const Icon(Icons.person_outline, size: 18), label: Text(u['segMe'])),
          ButtonSegment(value: 'groups', icon: const Icon(Icons.groups_outlined, size: 18), label: Text(u['segGroups'])),
        ],
        selected: {c.statsView},
        onSelectionChanged: (value) => c.update(() => c.statsView = value.first),
      ),
    );
    final header = Row(children: [
      Expanded(child: Heading(t.stats, size: 26)),
      if (c.statsView == 'me')
        IconButton.filledTonal(
          tooltip: u['shareStats'],
          onPressed: () => showShareStats(context, c, v),
          icon: const Icon(Icons.ios_share),
        ),
    ]);
    if (c.statsView == 'groups') {
      return Gap(space: 14, children: [header, switcher, GroupsView(c: c)]);
    }
    final p = planText(lang);
    return Gap(space: 14, children: [
      header,
      switcher,
      Panel(
        child: Gap(space: 10, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: formattedPercent(v.percentExact, lang),
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: palette.foreground, height: 1)),
              TextSpan(text: ' %', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: palette.foreground)),
            ])),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Muted(fill(u['cardRead'], {'scope': v.fixed ? 'Bibelleseplan 52' : p[s.config.scope ?? 'bible']})),
              ),
            ),
          ]),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v.percentExact / 100, minHeight: 10),
          ),
          FinePrint(fill(u['chaptersOf'], {'done': fmt.number(v.doneCount), 'total': fmt.number(v.scoped.length)})),
          Details(summary: u['progressHow'], children: [
            Text(u['progressExplain']),
            FinePrint(u['progressSource']),
          ]),
        ]),
      ),
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
      BookOverview(c: c, v: v),
      Panel(
        child: Gap(children: [
          Row(children: [
            Icon(Icons.schedule, color: palette.ring),
            const SizedBox(width: 8),
            Expanded(child: Heading(t.paceTitle, size: 19)),
          ]),
          Text(wpm == null ? u['paceNone'] : fill(u['wpm'], {'n': wpm}),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (v.pace.personal || v.pace.learning)
            Muted(t.paceBased.replaceFirst('{chapters}', '${v.pace.chapters}').replaceFirst('{time}', fmt.time(v.pace.seconds))),
          Muted(e.paceHelp, size: 13),
          if (v.pace.excluded > 0) Notice(text: '${e.excluded}: ${v.pace.excluded}'),
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
          Heading(u['recentTitle'], size: 19),
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
        ]),
      ),
      Panel(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Details(summary: u['timeDetails'], children: [ReadingTimeOverview(summary: v.timeSummary, lang: lang)]),
      ),
    ]);
  }
}

/// One tile per book, filled by the share of chapters read.
class BookOverview extends StatelessWidget {
  const BookOverview({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  @override
  Widget build(BuildContext context) {
    final x = featureText(c.lang);
    final names = bookNames(c.lang) ?? [for (final b in bibleBooks) b.name];
    final palette = context.palette;
    final books = bookProgress(v.state);
    final share = bookTextShare(v.state);
    return Panel(
      child: Gap(children: [
        Heading(x['books'], size: 19),
        Muted(x['booksSub']),
        LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth > 520 ? 4 : 3;
          final width = (box.maxWidth - (columns - 1) * 6) / columns;
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (index, read, total) in books)
              Semantics(
                label: '${names[index]}: $read / $total',
                child: Container(
                  width: width,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.muted,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: read == total ? palette.primary : palette.border),
                  ),
                  child: Stack(children: [
                    FractionallySizedBox(
                      widthFactor: (share[index] ?? read / total).clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: Container(color: read == total ? palette.primary : palette.accent),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(names[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: read == total ? palette.onPrimary : palette.foreground)),
                        Text('$read/$total',
                            style: TextStyle(
                                fontSize: 11, color: read == total ? palette.onPrimary : palette.mutedForeground)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}
