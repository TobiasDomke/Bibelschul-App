import 'dart:ui' as ui_engine;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../app/reading_stats.dart';
import '../core/exports.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Share statistics": a picture of the own progress to send to friends, and
/// the full table (CSV) for those who want to work with the numbers.
Future<void> showShareStats(BuildContext context, AppController c, PlanView v) =>
    showDialog<void>(context: context, builder: (_) => _ShareDialog(c: c, v: v));

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.c, required this.v});
  final AppController c;
  final PlanView v;
  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _card = GlobalKey();
  bool working = false;

  Future<void> _shareImage() async {
    final lang = widget.c.lang;
    setState(() => working = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui_engine.ImageByteFormat.png);
      final ok = await shareBytes(data!.buffer.asUint8List(), 'leseweg-statistik.png', 'image/png',
          text: fill(ui(lang)['shareStatsText'], {'percent': formattedPercent(widget.v.percentExact, lang)}));
      if (!ok && mounted) _failed();
    } catch (_) {
      if (mounted) _failed();
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _shareCsv() async {
    final ok = await shareFile(csvFile(widget.v.state, widget.c.lang), 'leseweg-statistik.csv', 'text/csv');
    if (!ok && mounted) _failed();
  }

  void _failed() => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(nativeText(widget.c.lang).shareFailed)));

  @override
  Widget build(BuildContext context) {
    final lang = widget.c.lang;
    final u = ui(lang), t = text(lang);
    return AlertDialog(
      title: Text(u['shareStats']),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Gap(crossAxisAlignment: CrossAxisAlignment.center, children: [
            FittedBox(
              child: RepaintBoundary(key: _card, child: StatsCard(c: widget.c, v: widget.v)),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: working ? null : _shareImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(u['shareImage']),
              ),
            ),
            TextButton.icon(
              onPressed: working ? null : _shareCsv,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: Text(u['shareCsv']),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))],
    );
  }
}

/// The picture itself: progress, streak, chapters, time and speed.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.c, required this.v});
  final AppController c;
  final PlanView v;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final u = ui(lang), p = planText(lang);
    final fmt = Fmt(lang);
    final palette = Palette.light;
    final s = v.state;
    final streak = readingStreak(s, v.currentDate);
    final wpm = wordsPerMinute(v.pace);
    const white = Colors.white;
    final muted = palette.previewMuted;
    Widget metric(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: muted, fontSize: 12)),
          ]),
        );
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(22)),
      child: DefaultTextStyle(
        style: const TextStyle(color: white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.menu_book, color: white, size: 18),
            const SizedBox(width: 8),
            const Text('Leseweg', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            Text(fmt.date(v.currentDate, long: true), style: TextStyle(color: muted, fontSize: 12)),
          ]),
          const SizedBox(height: 18),
          Text(u['cardTitle'], style: TextStyle(color: muted, fontSize: 13, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: formattedPercent(v.percentExact, lang),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.05)),
            const TextSpan(text: ' %', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ])),
          Text(fill(u['cardRead'], {'scope': v.fixed ? 'Bibelleseplan 52' : p[s.config.scope ?? 'bible']}),
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: v.percentExact / 100,
              minHeight: 8,
              color: white,
              backgroundColor: white.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            metric('${fmt.number(v.doneCount)} / ${fmt.number(v.scoped.length)}', u['statChapters']),
            metric(streak == 0 ? '–' : fill(streak == 1 ? u['valueDay'] : u['valueDays'], {'n': streak}),
                u['statStreak']),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            metric(v.totalSeconds == 0 ? '–' : fmt.time(v.totalSeconds), u['statTime']),
            metric(wpm == null ? '–' : fill(u['valueSpeed'], {'n': wpm}), u['statSpeed']),
          ]),
          const SizedBox(height: 16),
          Text('leseweg.pages.dev', style: TextStyle(color: muted, fontSize: 11.5)),
        ]),
      ),
    );
  }
}
