import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/data.g.dart';
import '../core/languages.dart';
import '../core/planner.dart';
import '../core/reading_time.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Why these chapters together?" for the chronological order (app/reading-context.tsx).
class ReadingContext extends StatelessWidget {
  const ReadingContext({super.key, required this.config, required this.items, required this.lang});
  final Config config;
  final List<Chapter> items;
  final Lang lang;
  @override
  Widget build(BuildContext context) {
    if (config.order != 'chronological' && config.order != 'chronoPsalms') return const SizedBox.shrink();
    final ids = {for (final c in items) c.id};
    final groups = historicalGroupsFor(config.edition)
        .where((g) => g.kind != null && g.chapters.any((c) => ids.contains(c.id)))
        .toList();
    final u = ui(lang);
    final companions = companionPsalms(config);
    final psalms = [
      for (final c in items)
        if (psalmAnchor(config, c.id) case final anchor?) (c, anchor),
    ];
    final companion = items.where((c) => companions.contains(c.id)).toList();
    if (groups.isEmpty && psalms.isEmpty && companion.isEmpty) return const SizedBox.shrink();
    final p = planText(lang), names = bookNames(lang);
    return Details(summary: p.why, children: [
      for (final (psalm, anchor) in psalms)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(passage([psalm], names), style: const TextStyle(fontWeight: FontWeight.w700)),
          Muted(fill(u['psalmBelongs'], {'passage': passage([anchor], names)})),
        ]),
      if (companion.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(passage(companion, names), style: const TextStyle(fontWeight: FontWeight.w700)),
          Muted(u['companionPsalm']),
        ]),
      for (final g in groups)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(passage(g.chapters, names), style: const TextStyle(fontWeight: FontWeight.w700)),
          Muted(p[g.kind!]),
        ]),
      FinePrint(p.contextNote),
    ]);
  }
}

/// Notice after the Joel/Malachi chapter correction (app/chapter-correction.tsx).
class ChapterCorrectionNotice extends StatelessWidget {
  const ChapterCorrectionNotice({super.key, required this.state, required this.lang});
  final ReadingState state;
  final Lang lang;
  @override
  Widget build(BuildContext context) {
    final correction = state.chapterCorrection;
    if (correction == null) return const SizedBox.shrink();
    final t = chapterCorrectionText(lang), names = bookNames(lang);
    String label(String ref) {
      final [code, number] = ref.split(' ');
      final index = bibleBooks.indexWhere((b) => b.code == code);
      return '${index >= 0 ? (names?[index] ?? bibleBooks[index].name) : code} $number';
    }

    return Notice(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(t.help),
        const SizedBox(height: 4),
        Text(t.times),
        Details(summary: t.archive, children: [
          if (correction.previouslyRead.isNotEmpty) Text('${t.previous}: ${correction.previouslyRead.map(label).join(' · ')}'),
          if (correction.done.isNotEmpty)
            Text('${t.done}: ${correction.done.entries.map((e) => '${label(e.key)} (${e.value})').join(' · ')}'),
          if (correction.samples.isNotEmpty) Text('${t.measurements}: ${correction.samples.length}'),
        ]),
      ]),
    );
  }
}

/// Reading time until the goal (app/reading-time-overview.tsx).
class ReadingTimeOverview extends StatelessWidget {
  const ReadingTimeOverview({super.key, required this.summary, required this.lang, this.previousEntered = false});
  final ReadingTimeSummary summary;
  final Lang lang;

  /// The earlier reading time was entered by the reader, not estimated.
  final bool previousEntered;
  @override
  Widget build(BuildContext context) {
    final t = readingTimeText(lang), p = planText(lang);
    final palette = context.palette;
    Widget row(String label, double seconds, {String? small, bool strong = false, bool total = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: total ? palette.foreground : palette.border, width: total ? 1.5 : 1)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: strong || total ? FontWeight.w700 : FontWeight.w400)),
                if (small != null) Muted(small, size: 12.5),
              ]),
            ),
            const SizedBox(width: 12),
            Text(readingTime(seconds, lang),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: total ? 17 : 15, color: palette.foreground)),
          ]),
        );
    return Panel(
      child: Gap(children: [
        Heading(t.title, size: 19),
        Column(children: [
          if (summary.previousChapters > 0 || previousEntered)
            row(previousEntered ? ui(lang)['pastEntered'] : p.estimatedPast, summary.previousSeconds),
          if (summary.unmeasuredChapters > 0) row(t.unmeasured, summary.unmeasuredSeconds),
          row(t.past, summary.pastSeconds, strong: true),
          row(t.remaining, summary.remainingSeconds,
              small: '${summary.remainingChapters} ${text(lang).chaptersRemaining}'),
          row(t.total, summary.totalSeconds, total: true),
        ]),
        FinePrint(t.help),
        if (summary.unmeasuredChapters > 0) FinePrint(t.unmeasuredHelp),
      ]),
    );
  }
}

/// Upcoming-day row with a date square (used on Today and in the plan list).
class DateSquare extends StatelessWidget {
  const DateSquare({super.key, required this.top, required this.bottom});
  final String top, bottom;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(top, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.foreground)),
        Text(bottom, style: TextStyle(fontSize: 11, color: p.mutedForeground), overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Percent with two decimals ("0,27", "42,10"). Rounded down, so the display
/// never runs ahead of the reading: never "100" before the last chapter and
/// never "0,00" once something was read.
String formattedPercent(double percent, Lang lang) {
  if (percent <= 0) return NumberFormat.decimalPatternDigits(locale: locales[lang], decimalDigits: 2).format(0);
  if (percent >= 100) return NumberFormat.decimalPatternDigits(locale: locales[lang], decimalDigits: 2).format(100);
  var value = (percent * 100).floor() / 100;
  if (value <= 0) value = 0.01;
  if (value >= 100) value = 99.99;
  return NumberFormat.decimalPatternDigits(locale: locales[lang], decimalDigits: 2).format(value);
}
