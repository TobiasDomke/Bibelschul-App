import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/adaptive.dart';
import '../core/deadline.dart';
import '../core/languages.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/reading_time.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'theme.dart';
import 'widgets.dart';

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String body, required String confirm, required String cancel, Widget? extra}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Gap(children: [Text(body), ?extra])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirm)),
      ],
    ),
  );
  return result ?? false;
}

/// Change the target date with a live preview (app/deadline-dialog.tsx).
Future<void> showDeadlineDialog(BuildContext context, AppController c) => showDialog(
      context: context,
      builder: (_) => _DeadlineDialog(c: c),
    );

class _DeadlineDialog extends StatefulWidget {
  const _DeadlineDialog({required this.c});
  final AppController c;
  @override
  State<_DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<_DeadlineDialog> {
  late final ReadingState state = widget.c.state!;
  late String end = addDays(state.config.start, duration(state.config) - 1);

  @override
  Widget build(BuildContext context) {
    final lang = widget.c.lang;
    final t = text(lang), d = deadlineText(lang);
    final fmt = Fmt(lang);
    final date = today(state.config.timezone);
    final bounds = deadlineBounds(state, date);
    ReadingState? preview;
    if (state.timer == null) {
      try {
        preview = rescheduleDeadline(state, end, date);
      } catch (_) {}
    }
    var days = 0, count = 0;
    var estimate = 0.0;
    if (preview != null) {
      final start = dayIndex(preview.config, date);
      final remaining = [
        for (final (i, ids) in preview.adaptive!.days.skip(start).indexed)
          if (!preview.adaptive!.finished.contains(start + i)) ids,
      ];
      final inventory = chaptersFor(state.config.edition);
      final words = remaining.expand((x) => x).fold<int>(0, (s, id) => s + inventory[id].words);
      estimate = estimatedSeconds(words / max(1, remaining.length), readingPace(state));
      days = remaining.length;
      count = remaining.expand((x) => x).length;
    }
    return AlertDialog(
      title: Text(d.edit),
      content: SingleChildScrollView(
        child: Gap(children: [
          Text(d.help),
          DateField(
            label: d.end,
            value: end,
            first: bounds.min,
            last: bounds.max,
            display: (v) => fmt.date(v, long: true),
            enabled: !widget.c.busy,
            onChanged: (v) => setState(() => end = v),
          ),
          FinePrint(d.inclusive),
          if (state.timer != null)
            Notice(text: d.pause)
          else if (preview != null)
            Notice(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.preview, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(fill(d.remaining, {'chapters': count, 'days': days})),
                if (count > 0) Text(fill(d.estimate, {'time': readingTime(estimate, lang)})),
                if (count > 0 && estimate > 5400) Text(t.longDay),
                if (end == date && count > 0) Text(d.today),
              ]),
            )
          else
            Notice(
              kind: NoticeKind.error,
              text: fill(d.bounds, {'min': fmt.date(bounds.min, long: true), 'max': fmt.date(bounds.max, long: true)}),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: widget.c.busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: widget.c.busy || state.timer != null || preview == null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final updated = await widget.c.mutate({'action': 'deadline', 'end': end});
                  if (updated != null) {
                    widget.c.update(() {
                      widget.c.selected = null;
                      widget.c.page = dayIndex(updated.config, today(updated.config.timezone)) ~/ 14;
                      widget.c.message = 'deadline';
                    });
                    navigator.pop();
                  }
                },
          child: Text(widget.c.busy ? t.saving : t.save),
        ),
      ],
    );
  }
}

/// Correct the measured time of a reading unit (app/time-correction-dialog.tsx).
Future<void> showTimeCorrectionDialog(BuildContext context, AppController c, int day, int seconds) => showDialog(
      context: context,
      builder: (_) => _TimeCorrectionDialog(c: c, day: day, seconds: seconds),
    );

class _TimeCorrectionDialog extends StatefulWidget {
  const _TimeCorrectionDialog({required this.c, required this.day, required this.seconds});
  final AppController c;
  final int day, seconds;
  @override
  State<_TimeCorrectionDialog> createState() => _TimeCorrectionDialogState();
}

class _TimeCorrectionDialogState extends State<_TimeCorrectionDialog> {
  late final hours = TextEditingController(text: '${widget.seconds ~/ 3600}');
  late final minutes = TextEditingController(text: '${(widget.seconds ~/ 60) % 60}');
  late final seconds = TextEditingController(text: '${widget.seconds % 60}');

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  int? get value => correctionSeconds(hours: hours.text, minutes: minutes.text, seconds: seconds.text);

  @override
  Widget build(BuildContext context) {
    final lang = widget.c.lang;
    final t = text(lang), d = readingTimeText(lang);
    final valid = value != null;
    Widget field(String label, TextEditingController controller) => Expanded(
          child: TextField(
            controller: controller,
            enabled: !widget.c.busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
            onChanged: (_) => setState(() {}),
          ),
        );
    return AlertDialog(
      title: Text(t.editTime),
      content: SingleChildScrollView(
        child: Gap(children: [
          Text(d.correction),
          Row(children: [
            field(d.hours, hours),
            const SizedBox(width: 8),
            field(d.minutes, minutes),
            const SizedBox(width: 8),
            field(d.seconds, seconds),
          ]),
          if (!valid) Notice(text: d.invalidCorrection, kind: NoticeKind.error),
        ]),
      ),
      actions: [
        TextButton(onPressed: widget.c.busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: widget.c.busy || !valid
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final ok = await widget.c.mutate({'action': 'correct', 'day': widget.day, 'minutes': value! / 60});
                  if (ok != null) navigator.pop();
                },
          child: Text(widget.c.busy ? t.saving : t.save),
        ),
      ],
    );
  }
}

/// "Finish reading": review chapters, then save and redistribute (finishing dialog in leseweg.tsx).
Future<void> showFinishDialog(BuildContext context, AppController c) => showDialog(
      context: context,
      builder: (_) => ListenableBuilder(listenable: c, builder: (context, _) => _FinishDialog(c: c)),
    );

class _FinishDialog extends StatefulWidget {
  const _FinishDialog({required this.c});
  final AppController c;
  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  bool confirmPace = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final v = PlanView.of(c);
    if (v == null) return const SizedBox.shrink();
    final lang = c.lang;
    final t = text(lang), e = experienceText(lang), f = bible52Text(lang), time = readingTimeText(lang);
    final fmt = Fmt(lang);
    final checked = v.sessionItems.where((ch) => v.doneSet.containsKey(ch.id)).length;
    final palette = context.palette;
    return AlertDialog(
      title: Text(e.finish),
      content: SingleChildScrollView(
        child: Gap(children: [
          Text(v.fixed ? f.finish : t.finishExplanation),
          if (v.unusual)
            Notice(
              kind: NoticeKind.warning,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.outlier),
                CheckRow(
                  value: confirmPace,
                  title: e.confirmPace,
                  onChanged: (x) => setState(() => confirmPace = x),
                ),
              ]),
            ),
          for (final ch in v.sessionItems)
            CheckRow(
              value: v.doneSet.containsKey(ch.id),
              title: v.readLabel([ch]),
              onChanged: c.busy || (v.fixed && v.priorIds.contains(ch.id))
                  ? null
                  : (x) => c.mutate({'action': 'chapter', 'chapter': ch.id, 'done': x}),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: c.busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      showTimeCorrectionDialog(context, c, v.day.index, v.seconds);
                    },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(t.editTime),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: palette.muted, borderRadius: BorderRadius.circular(12)),
            child: Gap(space: 4, children: [
              Text('$checked ${t.chaptersChecked}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${v.remainingChapters} ${t.chaptersRemaining}'),
              if (v.fixed)
                Text(f.original)
              else if (v.remainingChapters == 0)
                Text(t.completePlan)
              else if (v.remainingDays > 0)
                Text(
                    '${v.remainingDays} ${t.daysRemaining} · ${t.approx} ${readingTime(estimatedSeconds(v.remainingWords / v.remainingDays, v.finishingPace(confirmPace)), lang)} ${time.daily}')
              else
                Notice(text: t.noDaysRemaining, kind: NoticeKind.warning),
              if (!v.fixed && v.days.isNotEmpty) Text('${t.target}: ${fmt.date(v.days.last.date, long: true)}'),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: c.busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: c.busy
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final fixed = v.fixed;
                  final updated = await c.mutate({
                    'action': 'complete',
                    'day': v.day.index,
                    if (v.unusual) 'paceChoice': confirmPace ? 'confirmed' : 'excluded',
                  });
                  if (updated != null) {
                    c.update(() {
                      c.message = fixed ? 'saved' : 'replanned';
                      c.selected = null;
                    });
                    navigator.pop();
                  }
                },
          child: Text(c.busy ? t.saving : (v.fixed ? f.save : t.finishAndReplan)),
        ),
      ],
    );
  }
}

/// Converts a language to the text used in dropdowns.
String langLabel(Lang l) => languageLabels[l]!;
