import 'package:flutter/material.dart';

import '../core/data.g.dart';
import '../core/languages.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import 'small_parts.dart';
import 'theme.dart';
import 'widgets.dart';

/// Chapters read before the plan, marked as fast as possible:
/// "read up to …" in Bible order, whole testaments, whole books with one tap,
/// and for a book in progress "read up to chapter …" or single chapters.
class PreviousPicker extends StatefulWidget {
  const PreviousPicker({
    super.key,
    required this.config,
    required this.value,
    required this.onChanged,
    required this.lang,
    this.locked = const [],
    this.disabled = false,
  });
  final Config config;
  final List<int> value;
  final ValueChanged<List<int>> onChanged;
  final Lang lang;
  final List<int> locked;
  final bool disabled;
  @override
  State<PreviousPicker> createState() => _PreviousPickerState();
}

class _PreviousPickerState extends State<PreviousPicker> {
  String search = '';
  int? untilBook;
  final untilChapter = TextEditingController();
  String untilError = '';

  @override
  void dispose() {
    untilChapter.dispose();
    super.dispose();
  }

  void change(Iterable<int> ids, bool checked) {
    final fixed = widget.locked.toSet();
    final next = widget.value.toSet();
    for (final id in ids) {
      if (fixed.contains(id)) continue;
      checked ? next.add(id) : next.remove(id);
    }
    widget.onChanged(next.toList()..sort());
  }

  /// Everything from the start of the plan's books up to the given chapter.
  void markUntil(List<Chapter> scope) {
    final u = ui(widget.lang);
    final book = untilBook;
    final chapters = book == null ? const <Chapter>[] : scope.where((c) => c.bookIndex == book).toList();
    final number = int.tryParse(untilChapter.text.trim());
    if (book == null || number == null || number < 1 || number > chapters.length) {
      setState(() => untilError = u['untilInvalid']);
      return;
    }
    final last = chapters.firstWhere((c) => c.number == number);
    final position = scope.indexOf(last);
    setState(() => untilError = '');
    change(scope.take(position + 1).map((c) => c.id), true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final p = planText(lang), u = ui(lang);
    final palette = context.palette;
    final names = bookNames(lang) ?? [for (final b in bibleBooks) b.name];
    final selected = widget.value.toSet(), fixed = widget.locked.toSet();
    final scope = scopeFor(widget.config); // Bible order of the reader's edition
    final books = <int, List<Chapter>>{};
    for (final c in scope) {
      (books[c.bookIndex] ??= []).add(c);
    }
    bool isRead(Chapter c) => selected.contains(c.id) || fixed.contains(c.id);
    final totalWords = scope.fold<int>(0, (s, c) => s + c.words);
    final readWords = scope.where(isRead).fold<int>(0, (s, c) => s + c.words);
    final query = search.trim().toLowerCase();
    final sections = [
      (u['oldTestament'], [for (final b in books.keys) if (b < 39) b]),
      (u['newTestament'], [for (final b in books.keys) if (b >= 39) b]),
    ].where((s) => s.$2.isNotEmpty).toList();

    return Gap(space: 14, children: [
      // Summary of the selection.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.auto_stories_outlined, color: palette.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fill(u['previousSummary'], {
                'books': books.values.where((cs) => cs.every(isRead)).length,
                'chapters': scope.where(isRead).length,
                'percent': formattedPercent(totalWords == 0 ? 0 : readWords / totalWords * 100, lang),
              }),
              style: TextStyle(fontWeight: FontWeight.w600, color: palette.foreground),
            ),
          ),
          if (widget.value.isNotEmpty)
            TextButton(onPressed: widget.disabled ? null : () => widget.onChanged([]), child: Text(p.none)),
        ]),
      ),
      // Read straight through up to a point.
      Panel(
        padding: const EdgeInsets.all(14),
        child: Gap(space: 10, children: [
          Text(u['untilTitle'], style: TextStyle(fontWeight: FontWeight.w700, color: palette.foreground)),
          Muted(u['untilHelp'], size: 13),
          Row(children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: untilBook,
                hint: Text(u['untilBook']),
                items: [for (final b in books.keys) DropdownMenuItem(value: b, child: Text(names[b], overflow: TextOverflow.ellipsis))],
                onChanged: widget.disabled ? null : (b) => setState(() => untilBook = b),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: untilChapter,
                enabled: !widget.disabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: u['chapterLabel'],
                  helperText: untilBook == null ? null : '1–${books[untilBook]!.length}',
                ),
              ),
            ),
          ]),
          OutlinedButton.icon(
            onPressed: widget.disabled ? null : () => markUntil(scope),
            icon: const Icon(Icons.done_all, size: 18),
            label: Text(u['untilMark']),
          ),
          if (untilError.isNotEmpty) Notice(text: untilError, kind: NoticeKind.error),
        ]),
      ),
      TextField(
        enabled: !widget.disabled,
        decoration: InputDecoration(hintText: p.search, prefixIcon: const Icon(Icons.search)),
        onChanged: (v) => setState(() => search = v),
      ),
      for (final (title, bookIds) in sections)
        () {
          final visible = [for (final b in bookIds) if (names[b].toLowerCase().contains(query)) b];
          if (visible.isEmpty) return const SizedBox.shrink();
          final all = [for (final b in bookIds) ...books[b]!];
          final count = all.where(isRead).length;
          return Container(
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              // Whole testament.
              Material(
                color: palette.muted,
                child: CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  tristate: true,
                  value: count == all.length ? true : (count > 0 ? null : false),
                  onChanged: widget.disabled ? null : (_) => change(all.map((c) => c.id), count != all.length),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  secondary: Muted('$count / ${all.length}', size: 13),
                ),
              ),
              for (final b in visible)
                _BookRow(
                  name: names[b],
                  chapters: books[b]!,
                  selected: selected,
                  fixed: fixed,
                  lang: lang,
                  disabled: widget.disabled,
                  change: change,
                ),
            ]),
          );
        }(),
    ]);
  }
}

class _BookRow extends StatefulWidget {
  const _BookRow({
    required this.name,
    required this.chapters,
    required this.selected,
    required this.fixed,
    required this.lang,
    required this.disabled,
    required this.change,
  });
  final String name;
  final List<Chapter> chapters;
  final Set<int> selected, fixed;
  final Lang lang;
  final bool disabled;
  final void Function(Iterable<int>, bool) change;
  @override
  State<_BookRow> createState() => _BookRowState();
}

class _BookRowState extends State<_BookRow> {
  bool open = false;
  late final until = TextEditingController();
  bool error = false;

  @override
  void dispose() {
    until.dispose();
    super.dispose();
  }

  /// "Read up to chapter n": 1–n read, the rest of the book open.
  void readUntil() {
    final n = int.tryParse(until.text.trim());
    if (n == null || n < 1 || n > widget.chapters.length) {
      setState(() => error = true);
      return;
    }
    setState(() => error = false);
    widget.change(widget.chapters.where((c) => c.number <= n).map((c) => c.id), true);
    widget.change(widget.chapters.where((c) => c.number > n).map((c) => c.id), false);
  }

  @override
  Widget build(BuildContext context) {
    final p = planText(widget.lang), u = ui(widget.lang);
    final cs = widget.chapters;
    bool isRead(Chapter c) => widget.selected.contains(c.id) || widget.fixed.contains(c.id);
    final count = cs.where(isRead).length;
    final palette = context.palette;
    final allFixed = cs.every((c) => widget.fixed.contains(c.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Divider(height: 1, color: palette.border),
      Row(children: [
        Checkbox(
          tristate: true,
          value: count == cs.length ? true : (count > 0 ? null : false),
          onChanged: widget.disabled || allFixed ? null : (_) => widget.change(cs.map((c) => c.id), count != cs.length),
          semanticLabel: '${p.wholeBook}: ${widget.name}',
        ),
        Expanded(
          child: InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Text(widget.name,
                      style: TextStyle(
                          color: palette.foreground,
                          fontWeight: count > 0 && count < cs.length ? FontWeight.w600 : FontWeight.w400)),
                ),
                Muted(count == 0 ? '${cs.length}' : '$count / ${cs.length}', size: 13),
                const SizedBox(width: 4),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: palette.mutedForeground),
                const SizedBox(width: 10),
              ]),
            ),
          ),
        ),
      ]),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Gap(space: 10, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: until,
                  enabled: !widget.disabled,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: u['readUntilChapter'], helperText: '1–${cs.length}'),
                  onSubmitted: (_) => readUntil(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: widget.disabled ? null : readUntil, child: Text(u['apply'])),
            ]),
            if (error) Notice(text: p.rangeInvalid, kind: NoticeKind.error),
            Muted(u['tapChapters'], size: 12.5),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in cs)
                Tooltip(
                  message: widget.fixed.contains(c.id) ? p.duringPlan : '${widget.name} ${c.number}',
                  child: FilterChip(
                    label: Text('${c.number}'),
                    selected: isRead(c),
                    showCheckmark: false,
                    selectedColor: palette.accent,
                    onSelected: widget.disabled || widget.fixed.contains(c.id) ? null : (v) => widget.change([c.id], v),
                  ),
                ),
            ]),
          ]),
        ),
    ]);
  }
}

/// Hours, minutes and seconds for the time spent on earlier reading.
/// Empty fields mean "let Leseweg estimate".
class DurationFields extends StatefulWidget {
  const DurationFields({super.key, required this.seconds, required this.onChanged, required this.lang, this.estimate});
  final int? seconds;
  final ValueChanged<int?> onChanged;
  final Lang lang;

  /// Shown as a hint when nothing is entered.
  final String? estimate;
  @override
  State<DurationFields> createState() => _DurationFieldsState();
}

class _DurationFieldsState extends State<DurationFields> {
  late final hours = TextEditingController(text: widget.seconds == null ? '' : '${widget.seconds! ~/ 3600}');
  late final minutes = TextEditingController(text: widget.seconds == null ? '' : '${widget.seconds! ~/ 60 % 60}');
  late final seconds = TextEditingController(text: widget.seconds == null ? '' : '${widget.seconds! % 60}');
  bool error = false;

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  void update() {
    final texts = [hours.text.trim(), minutes.text.trim(), seconds.text.trim()];
    if (texts.every((t) => t.isEmpty)) {
      setState(() => error = false);
      widget.onChanged(null);
      return;
    }
    final [h, m, s] = [for (final t in texts) t.isEmpty ? 0 : int.tryParse(t)];
    final valid = h != null && m != null && s != null && h >= 0 && h <= 9999 && m >= 0 && m < 60 && s >= 0 && s < 60;
    setState(() => error = !valid);
    if (valid) widget.onChanged(h * 3600 + m * 60 + s);
  }

  @override
  Widget build(BuildContext context) {
    final u = ui(widget.lang);
    Widget field(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(labelText: label),
            onChanged: (_) => update(),
          ),
        );
    return Gap(space: 8, children: [
      Text(u['previousTimeTitle'], style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.foreground)),
      Muted(widget.estimate == null ? u['previousTimeHelp'] : fill(u['previousTimeEstimate'], {'time': widget.estimate!}),
          size: 13),
      Row(children: [
        field(hours, u['hours']),
        const SizedBox(width: 8),
        field(minutes, u['minutes']),
        const SizedBox(width: 8),
        field(seconds, u['seconds']),
      ]),
      if (error) Notice(text: u['durationInvalid'], kind: NoticeKind.error),
    ]);
  }
}
