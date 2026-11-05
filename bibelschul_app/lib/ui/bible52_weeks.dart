import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../core/planner.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// The same week/passage hierarchy for onboarding, later corrections and reading
/// (app/bible52-weeks.tsx). With [onChanged] it selects chapters; with
/// [onChoose] it opens a reading unit.
class Bible52Weeks extends StatefulWidget {
  const Bible52Weeks({
    super.key,
    required this.value,
    required this.lang,
    this.onChanged,
    this.locked = const [],
    this.disabled = false,
    this.onChoose,
    this.current = 0,
  });
  final List<int> value;
  final Lang lang;
  final ValueChanged<List<int>>? onChanged;
  final List<int> locked;
  final bool disabled;
  final ValueChanged<int>? onChoose;
  final int current;
  @override
  State<Bible52Weeks> createState() => _Bible52WeeksState();
}

class _Bible52WeeksState extends State<Bible52Weeks> {
  late int? expanded = widget.onChoose != null ? widget.current ~/ 7 : null;

  void change(Iterable<int> ids, bool checked) {
    final fixed = widget.locked.toSet();
    final next = widget.value.toSet();
    for (final id in ids.where((id) => !fixed.contains(id))) {
      checked ? next.add(id) : next.remove(id);
    }
    widget.onChanged?.call(next.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final t = bible52Text(widget.lang), p = planText(widget.lang);
    final palette = context.palette;
    final selected = widget.value.toSet(), fixed = widget.locked.toSet();
    bool read(int id) => selected.contains(id) || fixed.contains(id);
    return Gap(
      children: [
        if (widget.onChanged != null) ...[
          Text(fill(p.selected, {'count': widget.value.length}),
              style: TextStyle(fontWeight: FontWeight.w600, color: palette.foreground)),
          Wrap(spacing: 8, children: [
            TextButton(
              onPressed: widget.disabled
                  ? null
                  : () => change([for (final u in bible52Units) for (final c in u.chapters) c.id], true),
              child: Text(t.all),
            ),
            TextButton(
              onPressed: widget.disabled || widget.value.isEmpty ? null : () => widget.onChanged!([]),
              child: Text(t.none),
            ),
          ]),
        ] else
          Muted(t.selectHelp),
        Container(
          decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (final (week, units) in bible52Weeks.indexed) _week(context, week, units, read, fixed),
            ],
          ),
        ),
      ],
    );
  }

  Widget _week(BuildContext context, int week, List<Bible52Unit> units, bool Function(int) read, Set<int> fixed) {
    final t = bible52Text(widget.lang);
    final palette = context.palette;
    final ids = [for (final u in units) for (final c in u.chapters) c.id];
    final count = ids.where(read).length;
    final complete = units.where((u) => u.chapters.every((c) => read(c.id))).length;
    final isOpen = expanded == week;
    return Column(
      children: [
        Row(children: [
          if (widget.onChanged != null)
            Checkbox(
              tristate: true,
              value: count == ids.length ? true : (count > 0 ? null : false),
              semanticLabel: '${t.wholeWeek}: ${t.week} ${week + 1}',
              onChanged:
                  widget.disabled || ids.every(fixed.contains) ? null : (_) => change(ids, count != ids.length),
            ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => expanded = isOpen ? null : week),
              child: Padding(
                padding: EdgeInsets.fromLTRB(widget.onChanged == null ? 14 : 0, 14, 10, 14),
                child: Row(children: [
                  Text('${t.week} ${week + 1}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: palette.foreground)),
                  const Spacer(),
                  Muted('$complete/7 ${t.complete}', size: 13),
                  Icon(isOpen ? Icons.expand_more : Icons.chevron_right, color: palette.mutedForeground),
                ]),
              ),
            ),
          ),
        ]),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Column(children: [for (final u in units) _unit(context, week, u, read, fixed)]),
          ),
        Divider(height: 1, color: palette.border),
      ],
    );
  }

  Widget _unit(BuildContext context, int week, Bible52Unit u, bool Function(int) read, Set<int> fixed) {
    final t = bible52Text(widget.lang);
    final palette = context.palette;
    final n = u.chapters.where((c) => read(c.id)).length;
    final checked = n == u.chapters.length;
    final status = n > 0 ? (checked ? t.complete : '${t.partial} · $n/${u.chapters.length}') : t.remaining;
    final content = Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(u.label, style: TextStyle(fontWeight: FontWeight.w600, color: palette.foreground)),
        Muted(status, size: 12.5),
      ]),
    );
    if (widget.onChanged != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.disabled || u.chapters.every((c) => fixed.contains(c.id))
            ? null
            : () => change(u.chapters.map((c) => c.id), !checked),
        child: Row(children: [
          Checkbox(
            tristate: true,
            value: checked ? true : (n > 0 ? null : false),
            semanticLabel: '${t.week} ${week + 1}: ${u.label}',
            onChanged: widget.disabled || u.chapters.every((c) => fixed.contains(c.id))
                ? null
                : (_) => change(u.chapters.map((c) => c.id), !checked),
          ),
          content,
        ]),
      );
    }
    final current = u.index == widget.current;
    return Material(
      color: current ? palette.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onChoose?.call(u.index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: checked ? palette.primary : palette.muted,
              foregroundColor: checked ? palette.onPrimary : palette.foreground,
              child: checked ? const Icon(Icons.check, size: 17) : Text('${u.slot}', style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 12),
            content,
            Icon(Icons.chevron_right, size: 18, color: palette.mutedForeground),
          ]),
        ),
      ),
    );
  }
}
