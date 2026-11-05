import 'package:flutter/material.dart';

import 'theme.dart';

/// White rounded card (".panel" in the web app).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: Padding(padding: padding, child: child),
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: color ?? context.palette.ring,
        ),
      );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.size = 22});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: context.palette.foreground, height: 1.2),
      );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 14});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: size, color: context.palette.mutedForeground, height: 1.4));
}

class FinePrint extends StatelessWidget {
  const FinePrint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12.5, color: context.palette.mutedForeground, height: 1.4));
}

enum NoticeKind { info, warning, error }

/// ".notice", ".warning" and ".error" boxes.
class Notice extends StatelessWidget {
  const Notice({super.key, this.text, this.child, this.kind = NoticeKind.info, this.actions = const []});
  final String? text;
  final Widget? child;
  final NoticeKind kind;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = switch (kind) {
      NoticeKind.info => (p.accent, p.foreground),
      NoticeKind.warning => (p.warningBackground, p.warningForeground),
      NoticeKind.error => (p.destructive.withValues(alpha: 0.12), p.destructive),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg, fontSize: 14, height: 1.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text != null) Text(text!),
              ?child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// HTML <details>/<summary> equivalent.
class Details extends StatelessWidget {
  const Details({super.key, required this.summary, required this.children, this.initiallyExpanded = false});
  final String summary;
  final List<Widget> children;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(summary, style: TextStyle(fontWeight: FontWeight.w600, color: p.primary, fontSize: 14.5)),
        iconColor: p.primary,
        collapsedIconColor: p.primary,
        children: [
          for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

/// A labelled radio card (".plan-choice"). Must be placed inside a [ChoiceGroup].
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.enabled = true,
  });
  final T value;
  final String title;
  final String? subtitle;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final registry = RadioGroup.maybeOf<T>(context);
    final selected = registry?.groupValue == value;
    void onChanged(T v) => registry?.onChanged(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? p.accent : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? p.ring : p.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => onChanged(value) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  child: Radio<T>(value: value, toggleable: false, enabled: enabled),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: p.foreground)),
                        if (subtitle != null) ...[const SizedBox(height: 2), Muted(subtitle!, size: 13)],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Groups radio tiles so they share one selected value.
class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({super.key, required this.value, required this.onChanged, required this.children, this.label});
  final T value;
  final ValueChanged<T> onChanged;
  final List<Widget> children;
  final String? label;
  @override
  Widget build(BuildContext context) => RadioGroup<T>(
        groupValue: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) ...[FieldLabel(label!), const SizedBox(height: 8)],
            ...children,
          ],
        ),
      );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.palette.foreground),
      );
}

/// A simple dropdown with a label above it.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: value,
            key: ValueKey(value),
            isExpanded: true,
            items: [
              for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
          ),
        ],
      );
}

/// A checkbox row with a title and optional help text (".together-choice").
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.value, required this.onChanged, required this.title, this.help});
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String? help;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onChanged == null ? null : () => onChanged!(!(value ?? false)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                tristate: value == null,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: context.palette.foreground, fontWeight: FontWeight.w500)),
                      if (help != null) Muted(help!, size: 13),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Column with uniform spacing between children.
class Gap extends StatelessWidget {
  const Gap({super.key, required this.children, this.space = 12, this.crossAxisAlignment = CrossAxisAlignment.start});
  final List<Widget> children;
  final double space;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: space), child],
        ],
      );
}

/// Date field opening the platform date picker. Values are ISO dates.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.first,
    required this.last,
    required this.display,
    this.enabled = true,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String first;
  final String last;
  final String Function(String) display;
  final bool enabled;

  DateTime _local(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final firstDate = _local(first), lastDate = _local(last);
    var initial = _local(value);
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size.fromHeight(50),
            backgroundColor: context.palette.card,
          ),
          onPressed: !enabled
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: firstDate,
                    lastDate: lastDate,
                  );
                  if (picked != null) onChanged(_iso(picked));
                },
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(display(value)),
        ),
      ],
    );
  }
}
