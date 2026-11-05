import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/pace.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import 'dialogs.dart';
import 'notes_ui.dart';
import 'theme.dart';
import 'widgets.dart';

/// Details of one plan day in a sheet, so looking ahead or back never leaves
/// the current screen. Reading itself always happens on "Today".
Future<void> showDaySheet(BuildContext context, AppController c, int index) {
  final v = PlanView.of(c);
  if (v == null) return Future.value();
  // The 52-week plan lets readers open any unit: that happens on "Today".
  if (v.fixed) {
    c.choose(index);
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final view = PlanView.of(c);
        if (view == null || index >= view.days.length) return const SizedBox.shrink();
        return _DaySheet(c: c, v: view, index: index);
      },
    ),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.c, required this.v, required this.index});
  final AppController c;
  final PlanView v;
  final int index;

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang), u = ui(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final day = v.days[index];
    final isToday = index == v.dateIndex;
    final past = day.date.compareTo(v.currentDate) < 0;
    final finished = v.planState.adaptive?.finished.contains(index) ?? false;
    final seconds = daySeconds(v.state, index, v.now);
    final items = v.ordered(day.chapters);
    final note = c.noteFor(index);

    final status = finished
        ? u['dayFinished']
        : isToday
            ? u['dayToday']
            : past
                ? (items.isEmpty ? t.noReadingLogged : u['dayPast'])
                : u['dayPreview'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Gap(space: 12, children: [
          Eyebrow('${t.day} ${index + 1} / ${v.days.length} · ${fmt.date(day.date, long: true)}'),
          Heading(items.isEmpty ? (past ? t.noReadingLogged : t.rest) : v.readLabel(items), size: 21),
          Row(children: [
            Icon(finished ? Icons.check_circle : (isToday ? Icons.wb_sunny_outlined : Icons.info_outline),
                size: 18, color: finished ? palette.primary : palette.mutedForeground),
            const SizedBox(width: 8),
            Expanded(child: Muted(status)),
          ]),
          if (items.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                  color: palette.muted, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                for (final ch in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      // Only a marker: reading and checking happen on "Today".
                      SizedBox(
                        width: 18,
                        child: v.doneSet.containsKey(ch.id)
                            ? Icon(Icons.check, size: 18, color: palette.primary)
                            : Icon(Icons.fiber_manual_record, size: 8, color: palette.mutedForeground),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(v.readLabel([ch]))),
                      Muted('${t.approx} ${fmt.time(estimatedSeconds(ch.words, v.pace))}', size: 12.5),
                    ]),
                  ),
              ]),
            ),
          if (seconds > 0)
            Row(children: [
              Icon(Icons.schedule, size: 18, color: palette.mutedForeground),
              const SizedBox(width: 8),
              Expanded(child: Text(fill(u['dayMeasured'], {'time': fmt.time(seconds)}))),
            ]),
          if (note != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(12)),
              child: Text(note.text),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (isToday)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  c.choose(index);
                },
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(u['readNow']),
              ),
            if ((past || finished) && (seconds > 0 || finished))
              OutlinedButton.icon(
                onPressed: c.busy || v.state.timer != null
                    ? null
                    : () => showTimeCorrectionDialog(context, c, index, seconds),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t.editTime),
              ),
            if (past || finished)
              OutlinedButton.icon(
                onPressed: () => showNoteEditor(context, c,
                    day: index, date: day.date, passage: items.isEmpty ? fmt.date(day.date) : v.readLabel(items)),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(note == null ? u['addNote'] : u['editNote']),
              ),
          ]),
        ]),
      ),
    );
  }
}
