import 'package:flutter/material.dart';

import '../app/plan_view.dart';
import '../core/book_order.dart';
import '../core/deadline.dart';
import '../core/editions.dart';
import '../core/languages.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/i18n.dart';
import 'bible52_weeks.dart';
import 'book_order_control.dart';
import 'previous_picker.dart';
import 'theme.dart';
import 'widgets.dart';

/// Three-step plan setup with a live preview (app/planner-form.tsx).
class PlannerForm extends StatefulWidget {
  const PlannerForm({super.key, required this.lang, required this.onSave, required this.busy, required this.zone});
  final Lang lang;
  final void Function(Config config, List<int> previouslyRead) onSave;
  final bool busy;
  final String zone;
  @override
  State<PlannerForm> createState() => _PlannerFormState();
}

class _PlannerFormState extends State<PlannerForm> {
  bool dateMode = false;
  String end = '';
  int step = 0;
  List<int> previouslyRead = [];
  late Config draft = Config(
    edition: languageEdition(widget.lang),
    amount: 12,
    unit: 'months',
    start: today(widget.zone),
    time: '07:30',
    timezone: widget.zone,
    scope: 'bible',
    order: 'canonical',
    keepTogether: true,
    bookOrderMode: 'auto',
  );
  late final amountController = TextEditingController(text: '${draft.amount}');
  final _heading = GlobalKey();

  /// Like the web app's heading focus: show the top of the form for each step.
  void move(int next) {
    setState(() => step = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _heading.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250), alignment: 0.05);
      }
    });
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Config get config => isBible52(draft)
      ? bible52Config(draft)
      : (draft.copy()..bookOrder = draft.bookOrderMode == 'auto' ? languageBookOrder(widget.lang) : draft.bookOrder);

  ({List<Day> days, String error}) computed() {
    try {
      final c = config;
      return (
        days: createPlan(!isBible52(c) && dateMode ? planEndingOn(c, end) : c, previouslyRead),
        error: '',
      );
    } catch (_) {
      return (days: <Day>[], error: text(widget.lang).invalid);
    }
  }

  void setScope(String scope) {
    final next = draft.copy()..scope = scope;
    final allowed = {for (final c in scopeFor(next)) c.id};
    setState(() {
      draft = next;
      previouslyRead = previouslyRead.where(allowed.contains).toList();
    });
  }

  void submit() {
    if (step < 2) {
      move(step + 1);
      return;
    }
    var submitted = config;
    try {
      if (!isBible52(submitted) && dateMode) submitted = planEndingOn(submitted, end);
      createPlan(submitted, previouslyRead);
      widget.onSave(submitted, previouslyRead);
    } catch (_) {
      setState(() => draft = submitted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final t = text(lang), p = planText(lang), f = bible52Text(lang), d = deadlineText(lang);
    final e = experienceText(lang);
    final fmt = Fmt(lang);
    final c = config;
    final fixed = isBible52(c);
    final names = bookNames(fixed ? Lang.de : lang);
    final items = scopeFor(c);
    final result = computed();
    final remainingWords = result.days.fold<int>(0, (s, day) => s + day.words);
    final pace = readingPace(null);
    final perDay = result.days.isEmpty
        ? 0.0
        : remainingWords /
            (fixed
                ? (result.days.where((x) => x.chapters.isNotEmpty).length == 0
                    ? 1
                    : result.days.where((x) => x.chapters.isNotEmpty).length)
                : result.days.length);
    final palette = context.palette;
    final disabled = widget.busy;

    final steps = [p.stepPlan, p.stepProgress, p.stepTime];
    final form = Panel(
      child: Gap(
        space: 14,
        children: [
          Icon(Icons.calendar_month_outlined, color: palette.primary, size: 26),
          Heading(p.setup, key: _heading),
          Muted(p.setupHelp),
          Row(children: [
            for (final (i, label) in steps.indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: disabled ? null : () => move(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      decoration: BoxDecoration(
                        color: step == i ? palette.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: step == i ? palette.ring : palette.border),
                      ),
                      child: Column(children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: step == i ? palette.primary : palette.muted,
                          foregroundColor: step == i ? palette.onPrimary : palette.foreground,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(height: 4),
                        Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: palette.foreground, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          if (step == 0) ...[
            ChoiceGroup<bool>(
              label: f.type,
              value: fixed,
              onChanged: (value) => setState(() {
                previouslyRead = [];
                dateMode = false;
                draft = value
                    ? bible52Config(c)
                    : (c.copy()
                      ..template = null
                      ..edition = languageEdition(lang)
                      ..amount = 12
                      ..unit = 'months'
                      ..scope = 'bible'
                      ..order = 'canonical'
                      ..keepTogether = true
                      ..bookOrderMode = 'auto');
                amountController.text = '${draft.amount}';
              }),
              children: [
                for (final value in [false, true])
                  ChoiceTile<bool>(
                    value: value,
                    enabled: !disabled,
                    title: value ? 'Bibelleseplan 52' : f.flexible,
                    subtitle: value ? f.description : f.flexibleHelp,
                  ),
              ],
            ),
            if (fixed)
              Notice(text: f.fixed)
            else ...[
              ChoiceGroup<String>(
                label: p.scope,
                value: c.scope ?? 'bible',
                onChanged: setScope,
                children: [
                  for (final value in ['bible', 'ot', 'nt'])
                    ChoiceTile<String>(
                      value: value,
                      enabled: !disabled,
                      title: p[value],
                      subtitle: fill(p.booksChapters, {
                        'books': value == 'bible' ? 66 : (value == 'ot' ? 39 : 27),
                        'chapters': value == 'bible' ? 1189 : (value == 'ot' ? 929 : 260),
                      }),
                    ),
                ],
              ),
              Notice(
                child: Text('${e.edition}: ${editionName(c.edition)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Details(summary: e.advanced, children: [
                BookOrderControl(
                  config: c,
                  lang: lang,
                  disabled: disabled,
                  onChanged: (choice) => setState(() => draft = draft.copy()
                    ..bookOrderMode = choice == 'auto' ? 'auto' : 'manual'
                    ..bookOrder = choice == 'auto' ? languageBookOrder(lang) : choice),
                ),
              ]),
              ChoiceGroup<String>(
                label: p.order,
                value: c.order ?? 'canonical',
                onChanged: (value) => setState(() => draft = draft.copy()..order = value),
                children: [
                  for (final value in ['canonical', 'chronological', 'mixed'])
                    ChoiceTile<String>(
                      value: value,
                      enabled: !disabled,
                      title: p[value],
                      subtitle: p['${value}Help'],
                    ),
                ],
              ),
              CheckRow(
                value: c.keepTogether == true,
                title: p.together,
                help: p.togetherHelp,
                onChanged: disabled ? null : (v) => setState(() => draft = draft.copy()..keepTogether = v),
              ),
            ],
          ],
          if (step == 1) ...[
            Heading(p.previous, size: 18),
            Muted(fixed ? f.progressHelp : p.previousHelp),
            if (fixed)
              Bible52Weeks(
                value: previouslyRead,
                lang: lang,
                disabled: disabled,
                onChanged: (v) => setState(() => previouslyRead = v),
              )
            else
              PreviousPicker(
                config: c,
                value: previouslyRead,
                lang: lang,
                disabled: disabled,
                onChanged: (v) => setState(() => previouslyRead = v),
              ),
          ],
          if (step == 2) ...[
            if (!fixed) ...[
              ChoiceGroup<bool>(
                label: d.mode,
                value: dateMode,
                onChanged: (value) => setState(() {
                  if (value && end.isEmpty) end = result.days.isNotEmpty ? result.days.last.date : c.start;
                  dateMode = value;
                }),
                children: [
                  for (final value in [false, true])
                    ChoiceTile<bool>(
                      value: value,
                      enabled: !disabled,
                      title: value ? d.date : d.duration,
                    ),
                ],
              ),
              if (dateMode) ...[
                DateField(
                  label: d.end,
                  value: end.isEmpty ? c.start : end,
                  first: c.start,
                  last: isValidIsoDate(c.start) ? addDays(c.start, 3649) : '2100-12-31',
                  display: (v) => fmt.date(v, long: true),
                  enabled: !disabled,
                  onChanged: (v) => setState(() => end = v),
                ),
                FinePrint(d.inclusive),
              ] else ...[
                FieldLabel(p.period),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: amountController,
                      enabled: !disabled,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => draft = draft.copy()..amount = int.tryParse(v) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: c.unit,
                      items: [
                        DropdownMenuItem(value: 'days', child: Text(t.days)),
                        DropdownMenuItem(value: 'weeks', child: Text(t.weeks)),
                        DropdownMenuItem(value: 'months', child: Text(t.months)),
                      ],
                      onChanged: disabled ? null : (v) => setState(() => draft = draft.copy()..unit = v!),
                    ),
                  ),
                ]),
              ],
            ],
            DateField(
              label: fixed ? f.start : t.startDate,
              value: c.start,
              first: '2020-01-01',
              last: '2100-12-31',
              display: (v) => fmt.date(v, long: true),
              enabled: !disabled,
              onChanged: (v) => setState(() => draft = draft.copy()..start = v),
            ),
            if (fixed)
              Notice(text: f.startHelp)
            else
              Notice(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.auto_awesome_outlined, size: 18, color: palette.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.balanced, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(d.balanced),
                    ]),
                  ),
                ]),
              ),
            if (result.error.isNotEmpty) Notice(text: result.error, kind: NoticeKind.error),
            if (result.days.isNotEmpty && estimatedMinutes(perDay, pace) > 90)
              Notice(text: t.longDay, kind: NoticeKind.warning),
            if (items.length == previouslyRead.length) Notice(text: p.allDone),
          ],
          Row(children: [
            if (step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: disabled ? null : () => move(step - 1),
                  child: Text(p.back),
                ),
              ),
            if (step > 0) const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: disabled || (step == 2 && result.error.isNotEmpty) ? null : submit,
                child: Text(disabled ? t.saving : (step == 2 ? t.create : p.next)),
              ),
            ),
          ]),
        ],
      ),
    );

    final previewStyle = TextStyle(color: palette.previewForeground);
    final preview = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.previewBackground, borderRadius: BorderRadius.circular(16)),
      child: DefaultTextStyle.merge(
        style: previewStyle,
        child: Gap(space: 14, children: [
          Eyebrow(t.overview, color: palette.previewMuted),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(result.days.isNotEmpty ? fmt.time(estimatedSeconds(perDay, pace)) : '–',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: palette.previewForeground)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(readingTimeText(lang).daily),
                Text(t.estimate, style: TextStyle(fontSize: 12, color: palette.previewMuted)),
              ]),
            ),
          ]),
          _previewLine(Icons.menu_book_outlined,
              fixed ? 'Bibelleseplan 52' : '${p[c.scope ?? 'bible']} · ${p[c.order ?? 'canonical']}', palette),
          _previewLine(
              Icons.check_circle_outline,
              fill(p.coverage, {
                'total': items.length,
                'previous': previouslyRead.length,
                'completed': 0,
                'remaining': items.length - previouslyRead.length,
              }),
              palette),
          _previewLine(
              Icons.calendar_month_outlined,
              '${result.days.length} ${t.dayCount} · ${t.target}: ${result.days.isNotEmpty ? fmt.date(result.days.last.date, long: true) : '–'}',
              palette),
          Text(t.beginning, style: TextStyle(fontWeight: FontWeight.w700, color: palette.previewForeground)),
          for (final day in result.days.where((x) => !fixed || x.chapters.isNotEmpty).take(3))
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 34,
                child: Text(fixed ? '${day.index % 7 + 1}' : '${day.index + 1}'.padLeft(2, '0'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: palette.previewMuted)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(passage(day.chapters, names).isEmpty ? t.rest : passage(day.chapters, names),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${fixed ? bible52Position(day.index, lang) : fmt.date(day.date)} · ${day.words > 0 ? '${t.approx} ${fmt.time(estimatedSeconds(day.words, pace))}' : t.rest}',
                    style: TextStyle(fontSize: 12.5, color: palette.previewMuted),
                  ),
                ]),
              ),
            ]),
        ]),
      ),
    );

    return Gap(space: 16, children: [form, preview]);
  }

  Widget _previewLine(IconData icon, String value, Palette palette) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.previewMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      );
}
