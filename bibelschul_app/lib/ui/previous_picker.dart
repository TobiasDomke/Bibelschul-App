import 'package:flutter/material.dart';

import '../core/data.g.dart';
import '../core/languages.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Mark previously read books, chapter ranges or single chapters (app/previous-picker.tsx).
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

  void change(Iterable<int> ids, bool checked) {
    final fixed = widget.locked.toSet();
    final next = widget.value.toSet();
    for (final id in ids) {
      if (fixed.contains(id)) continue;
      checked ? next.add(id) : next.remove(id);
    }
    widget.onChanged(next.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final p = planText(widget.lang);
    final names = bookNames(widget.lang) ?? [for (final b in bibleBooks) b.name];
    final selected = widget.value.toSet(), fixed = widget.locked.toSet();
    final groups = <int, List<Chapter>>{};
    for (final c in scopeFor(widget.config)) {
      (groups[c.bookIndex] ??= []).add(c);
    }
    final visible = groups.entries
        .where((e) => names[e.key].toLowerCase().contains(search.trim().toLowerCase()))
        .toList();
    return Gap(
      children: [
        Text(fill(p.selected, {'count': widget.value.length}),
            style: TextStyle(fontWeight: FontWeight.w600, color: context.palette.foreground)),
        TextField(
          enabled: !widget.disabled,
          decoration: InputDecoration(hintText: p.search, prefixIcon: const Icon(Icons.search), labelText: p.search),
          onChanged: (v) => setState(() => search = v),
        ),
        Wrap(spacing: 8, children: [
          TextButton(
            onPressed: widget.disabled ? null : () => change(groups.values.expand((cs) => cs.map((c) => c.id)), true),
            child: Text(p.all),
          ),
          TextButton(
            onPressed: widget.disabled || widget.value.isEmpty ? null : () => widget.onChanged([]),
            child: Text(p.none),
          ),
        ]),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final MapEntry(key: index, value: cs) in visible)
                _BookRow(
                  name: names[index],
                  chapters: cs,
                  selected: selected,
                  fixed: fixed,
                  lang: widget.lang,
                  disabled: widget.disabled,
                  change: change,
                ),
              if (visible.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Muted(p.noBooks)),
            ],
          ),
        ),
      ],
    );
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
  late final first = TextEditingController(text: '1');
  late final last = TextEditingController(text: '${widget.chapters.length}');
  bool error = false;

  @override
  void dispose() {
    first.dispose();
    last.dispose();
    super.dispose();
  }

  void range(bool checked) {
    final a = int.tryParse(first.text), b = int.tryParse(last.text);
    if (a == null || b == null || a < 1 || b < a || b > widget.chapters.length) {
      setState(() => error = true);
      return;
    }
    setState(() => error = false);
    widget.change(widget.chapters.where((c) => c.number >= a && c.number <= b).map((c) => c.id), checked);
  }

  @override
  Widget build(BuildContext context) {
    final p = planText(widget.lang);
    final cs = widget.chapters;
    final count = cs.where((c) => widget.selected.contains(c.id) || widget.fixed.contains(c.id)).length;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              tristate: true,
              value: count == cs.length ? true : (count > 0 ? null : false),
              onChanged: widget.disabled || cs.every((c) => widget.fixed.contains(c.id))
                  ? null
                  : (_) => widget.change(cs.map((c) => c.id), count != cs.length),
              semanticLabel: '${p.wholeBook}: ${widget.name}',
            ),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => open = !open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Expanded(child: Text(widget.name, style: TextStyle(color: palette.foreground))),
                    Muted('$count / ${cs.length}', size: 13),
                    Icon(open ? Icons.expand_less : Icons.expand_more, color: palette.mutedForeground),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
          ],
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Gap(space: 10, children: [
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: first,
                  enabled: !widget.disabled,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: p.from),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                  controller: last,
                  enabled: !widget.disabled,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: p.to),
                )),
              ]),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: widget.disabled ? null : () => range(true), child: Text(p.mark)),
                TextButton(onPressed: widget.disabled ? null : () => range(false), child: Text(p.unmark)),
              ]),
              if (error) Notice(text: p.rangeInvalid, kind: NoticeKind.error),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in cs)
                    Tooltip(
                      message: widget.fixed.contains(c.id) ? p.duringPlan : '${widget.name} ${c.number}',
                      child: FilterChip(
                        label: Text('${c.number}'),
                        selected: widget.selected.contains(c.id) || widget.fixed.contains(c.id),
                        showCheckmark: false,
                        selectedColor: palette.accent,
                        onSelected: widget.disabled || widget.fixed.contains(c.id)
                            ? null
                            : (v) => widget.change([c.id], v),
                      ),
                    ),
                ],
              ),
            ]),
          ),
        Divider(height: 1, color: palette.border),
      ],
    );
  }
}
