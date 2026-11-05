import 'package:flutter/material.dart';

import '../app/plan_view.dart';
import '../core/book_order.dart';
import '../core/deadline.dart';
import '../core/editions.dart';
import '../core/languages.dart';
import '../core/pace.dart';
import '../core/planner.dart';
import '../core/reading_time.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import 'bible52_weeks.dart';
import 'book_order_control.dart';
import 'previous_picker.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the setup hands back: the plan, chapters read before and whether the
/// reader wants a daily reminder at `config.time`.
typedef PlanChoice = ({Config config, List<int> previouslyRead, bool remind, int? previousSeconds});

/// Plan setup. First a template (with the real daily reading time), then one
/// page for start, earlier reading and reminder. "Own plan" opens the full
/// three-step form. A live preview follows every choice.
class PlannerForm extends StatefulWidget {
  const PlannerForm({super.key, required this.lang, required this.onSave, required this.busy, required this.zone});
  final Lang lang;
  final void Function(PlanChoice choice) onSave;
  final bool busy;
  final String zone;
  @override
  State<PlannerForm> createState() => _PlannerFormState();
}

const _presetIds = ['bible', 'nt', 'chrono', 'mixed', '52'];

class _PlannerFormState extends State<PlannerForm> {
  /// null: choose a template · "custom": own plan (three steps) · otherwise a template id.
  String? preset;
  int step = 0;
  bool dateMode = false;
  bool remind = true;
  String end = '';
  List<int> previouslyRead = [];

  /// Entered time for the chapters read before (null: estimated).
  int? previousSeconds;
  late Config draft = _base();
  late final amountController = TextEditingController(text: '${draft.amount}');
  final _top = GlobalKey();

  /// Daily minutes per template, computed once from the real plans.
  late final Map<String, int> presetMinutes = {
    for (final id in _presetIds) id: _dailyMinutes(_presetConfig(id)),
  };

  Config _base() => Config(
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

  Config _presetConfig(String id) {
    final base = _base()..time = draft.time;
    return switch (id) {
      'nt' => base
        ..scope = 'nt'
        ..amount = 90
        ..unit = 'days',
      'chrono' => base..order = 'chronological',
      'mixed' => base..order = 'mixed',
      '52' => bible52Config(base),
      _ => base,
    };
  }

  int _dailyMinutes(Config config) {
    try {
      final c = isBible52(config) ? config : (config.copy()..bookOrder = languageBookOrder(widget.lang));
      final days = createPlan(c).where((d) => d.words > 0).toList();
      if (days.isEmpty) return 0;
      final words = days.fold<int>(0, (s, d) => s + d.words) / days.length;
      return estimatedMinutes(words, readingPace(null));
    } catch (_) {
      return 0;
    }
  }

  /// Shows the top of the form after switching pages.
  void _scrollUp() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _top.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250), alignment: 0.02);
        }
      });

  void choose(String? id) {
    setState(() {
      preset = id;
      step = 0;
      previouslyRead = [];
      dateMode = false;
      end = '';
      if (id != null) {
        draft = id == 'custom' ? _base() : _presetConfig(id);
        draft.start = today(widget.zone);
        amountController.text = '${draft.amount}';
      }
    });
    _scrollUp();
  }

  void move(int next) {
    setState(() => step = next);
    _scrollUp();
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
    var submitted = config;
    try {
      if (!isBible52(submitted) && dateMode) submitted = planEndingOn(submitted, end);
      createPlan(submitted, previouslyRead);
      widget.onSave((
        config: submitted,
        previouslyRead: previouslyRead,
        remind: remind,
        previousSeconds: previouslyRead.isEmpty ? null : previousSeconds,
      ));
    } catch (_) {
      setState(() => draft = submitted);
    }
  }

  Future<void> _editPrevious(BuildContext context) async {
    final result = await Navigator.of(context).push<(List<int>, int?)>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _PreviousPage(config: config, value: previouslyRead, seconds: previousSeconds, lang: widget.lang),
    ));
    if (result != null) {
      setState(() {
        previouslyRead = result.$1;
        previousSeconds = result.$2;
      });
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final [h, m] = draft.time.split(':').map(int.parse).toList();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (picked == null) return;
    setState(() => draft = draft.copy()
      ..time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  String _title(String id) {
    final u = ui(widget.lang);
    return u['preset_$id'];
  }

  @override
  Widget build(BuildContext context) {
    if (preset == null) return KeyedSubtree(key: _top, child: _chooser(context));
    final result = computed();
    return Gap(space: 16, children: [
      KeyedSubtree(key: _top, child: preset == 'custom' ? _custom(context, result) : _template(context, result)),
      _preview(context, result),
    ]);
  }

  // ----- Step 1: choose a template -----

  Widget _chooser(BuildContext context) {
    final u = ui(widget.lang);
    final palette = context.palette;
    final fmt = Fmt(widget.lang);
    Widget tile(String id, IconData icon, String title, String help, {String? trailing, bool outlined = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: outlined ? palette.background : palette.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), side: BorderSide(color: palette.border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.busy ? null : () => choose(id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: palette.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: palette.foreground)),
                      const SizedBox(height: 3),
                      Muted(help, size: 13),
                      if (trailing != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(20)),
                          child: Text(trailing,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.foreground)),
                        ),
                      ],
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: palette.mutedForeground),
                ]),
              ),
            ),
          ),
        );
    const icons = {
      'bible': Icons.menu_book_outlined,
      'nt': Icons.wb_sunny_outlined,
      'chrono': Icons.timeline,
      'mixed': Icons.shuffle,
      '52': Icons.calendar_view_week_outlined,
    };
    return Panel(
      child: Gap(space: 12, children: [
        Heading(u['chooseTitle'], size: 21),
        Muted(u['chooseHelp']),
        const SizedBox(height: 2),
        Column(children: [
          for (final id in _presetIds)
            tile(
              id,
              icons[id]!,
              _title(id),
              u['presetHelp_$id'],
              trailing: (presetMinutes[id] ?? 0) > 0
                  ? fill(u['perDay'], {'time': fmt.time((presetMinutes[id] ?? 0) * 60)})
                  : null,
            ),
          tile('custom', Icons.tune, u['customTitle'], u['customHelp'], outlined: true),
        ]),
      ]),
    );
  }

  // ----- Template chosen: one page -----

  Widget _template(BuildContext context, ({List<Day> days, String error}) result) {
    final lang = widget.lang;
    final u = ui(lang), t = text(lang);
    final fixed = isBible52(config);
    return Panel(
      child: Gap(space: 14, children: [
        Row(children: [
          Expanded(child: Eyebrow(u['chosenPlan'])),
          TextButton(onPressed: widget.busy ? null : () => choose(null), child: Text(u['change'])),
        ]),
        Heading(_title(preset!), size: 22),
        Muted(u['presetHelp_${preset!}']),
        const Divider(height: 8),
        ..._timeFields(context, result),
        _previousRow(context),
        _reminderRow(context),
        if (result.error.isNotEmpty) Notice(text: result.error, kind: NoticeKind.error),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.busy || result.error.isNotEmpty ? null : submit,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(widget.busy ? t.saving : u['startPlan']),
          ),
        ),
        if (fixed) FinePrint(bible52Text(lang).fixed),
      ]),
    );
  }

  // ----- Own plan: three steps -----

  Widget _custom(BuildContext context, ({List<Day> days, String error}) result) {
    final lang = widget.lang;
    final t = text(lang), p = planText(lang), u = ui(lang), e = experienceText(lang);
    final c = config;
    final palette = context.palette;
    final disabled = widget.busy;
    final steps = [p.stepPlan, p.stepProgress, u['stepTime']];

    final indicator = IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, label) in steps.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
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
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ],
      ]),
    );

    return Panel(
      child: Gap(space: 14, children: [
        Row(children: [
          Expanded(child: Heading(u['customTitle'], size: 21)),
          TextButton(onPressed: disabled ? null : () => choose(null), child: Text(u['change'])),
        ]),
        indicator,
        if (step == 0) ...[
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
                  subtitle: u['orderHelp_$value'],
                ),
            ],
          ),
          CheckRow(
            value: c.keepTogether == true,
            title: p.together,
            help: p.togetherHelp,
            onChanged: disabled ? null : (v) => setState(() => draft = draft.copy()..keepTogether = v),
          ),
          Details(summary: u['editionAndOrder'], children: [
            LabeledDropdown<String>(
              label: e.edition,
              value: draft.edition ?? languageEdition(lang),
              enabled: !disabled,
              items: [for (final id in editionIds) (id, editions[id]!.name)],
              onChanged: (id) => setState(() {
                draft = draft.copy()..edition = id;
                previouslyRead = [];
              }),
            ),
            FinePrint(u['editionHelp']),
            BookOrderControl(
              config: c,
              lang: lang,
              disabled: disabled,
              onChanged: (choice) => setState(() => draft = draft.copy()
                ..bookOrderMode = choice == 'auto' ? 'auto' : 'manual'
                ..bookOrder = choice == 'auto' ? languageBookOrder(lang) : choice),
            ),
          ]),
        ],
        if (step == 1) ...[
          Heading(p.previous, size: 18),
          Muted(u['readBeforeHelp']),
          PreviousPicker(
            config: c,
            value: previouslyRead,
            lang: lang,
            disabled: disabled,
            onChanged: (v) => setState(() => previouslyRead = v),
          ),
          if (previouslyRead.isNotEmpty)
            Panel(
              padding: const EdgeInsets.all(14),
              child: DurationFields(
                seconds: previousSeconds,
                lang: lang,
                estimate: previousEstimate(c, previouslyRead, lang),
                onChanged: (s) => previousSeconds = s,
              ),
            ),
        ],
        if (step == 2) ...[
          ..._timeFields(context, result),
          _reminderRow(context),
          if (result.error.isNotEmpty) Notice(text: result.error, kind: NoticeKind.error),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: disabled ? null : () => step == 0 ? choose(null) : move(step - 1),
              child: Text(p.back),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: disabled || (step == 2 && result.error.isNotEmpty) ? null : () => step < 2 ? move(step + 1) : submit(),
              child: Text(disabled ? t.saving : (step == 2 ? u['startPlan'] : p.next)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ----- Shared pieces -----

  List<Widget> _timeFields(BuildContext context, ({List<Day> days, String error}) result) {
    final lang = widget.lang;
    final t = text(lang), p = planText(lang), f = bible52Text(lang), d = deadlineText(lang), u = ui(lang);
    final fmt = Fmt(lang);
    final c = config;
    final fixed = isBible52(c);
    final disabled = widget.busy;
    final items = scopeFor(c);
    final remainingWords = result.days.fold<int>(0, (s, day) => s + day.words);
    final reading = result.days.where((x) => x.words > 0).length;
    final perDay = reading == 0 ? 0.0 : remainingWords / (fixed ? reading : result.days.length);
    return [
      if (!fixed) ...[
        FieldLabel(d.mode),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(d.duration)),
            ButtonSegment(value: true, label: Text(d.date)),
          ],
          selected: {dateMode},
          onSelectionChanged: disabled
              ? null
              : (value) => setState(() {
                    if (value.first && end.isEmpty) end = result.days.isNotEmpty ? result.days.last.date : c.start;
                    dateMode = value.first;
                  }),
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
              flex: 2,
              child: TextField(
                controller: amountController,
                enabled: !disabled,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => draft = draft.copy()..amount = int.tryParse(v) ?? 0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
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
        label: fixed ? f.start : u['firstDay'],
        value: c.start,
        first: '2020-01-01',
        last: '2100-12-31',
        display: (v) => fmt.date(v, long: true),
        enabled: !disabled,
        onChanged: (v) => setState(() => draft = draft.copy()..start = v),
      ),
      FinePrint(fixed ? f.startHelp : u['firstDayHelp']),
      if (result.days.isNotEmpty && estimatedMinutes(perDay, readingPace(null)) > 90)
        Notice(text: t.longDay, kind: NoticeKind.warning),
      if (items.length == previouslyRead.length) Notice(text: p.allDone),
    ];
  }

  Widget _previousRow(BuildContext context) {
    final u = ui(widget.lang);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.muted, borderRadius: BorderRadius.circular(12)),
      child: Gap(space: 8, children: [
        Text(u['readBefore'], style: TextStyle(fontWeight: FontWeight.w700, color: palette.foreground)),
        Muted(previouslyRead.isEmpty
            ? u['readBeforeHelp']
            : fill(u['readBeforeCount'], {'count': previouslyRead.length})),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(backgroundColor: palette.card),
          onPressed: widget.busy ? null : () => _editPrevious(context),
          icon: const Icon(Icons.check_box_outlined, size: 18),
          label: Text(previouslyRead.isEmpty ? u['readBeforeButton'] : u['readBeforeEdit']),
        ),
      ]),
    );
  }

  Widget _reminderRow(BuildContext context) {
    final u = ui(widget.lang);
    final palette = context.palette;
    return Material(
      color: palette.muted,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: remind,
          onChanged: widget.busy ? null : (v) => setState(() => remind = v),
          title: Text(u['remindTitle'], style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(u['remindHelp']),
        ),
        if (remind)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: palette.card),
            onPressed: widget.busy ? null : () => _pickTime(context),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(fill(u['remindAt'], {'time': draft.time})),
          ),
        ]),
      ),
    );
  }

  Widget _preview(BuildContext context, ({List<Day> days, String error}) result) {
    final lang = widget.lang;
    final t = text(lang), p = planText(lang), u = ui(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final c = config;
    final fixed = isBible52(c);
    final names = bookNames(fixed ? Lang.de : lang);
    final items = scopeFor(c);
    final pace = readingPace(null);
    final reading = result.days.where((x) => x.words > 0).length;
    final words = result.days.fold<int>(0, (s, day) => s + day.words);
    final perDay = reading == 0 ? 0.0 : words / (fixed ? reading : result.days.length);
    final open = items.length - previouslyRead.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.previewBackground, borderRadius: BorderRadius.circular(16)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: palette.previewForeground),
        child: Gap(space: 14, children: [
          Eyebrow(t.overview, color: palette.previewMuted),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(result.days.isNotEmpty ? fmt.time(estimatedSeconds(perDay, pace)) : '–',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: palette.previewForeground)),
            const SizedBox(width: 10),
            Expanded(child: Text(u['perDayEstimate'], style: TextStyle(color: palette.previewMuted))),
          ]),
          _line(Icons.menu_book_outlined,
              fixed ? _title('52') : '${p[c.scope ?? 'bible']} · ${p[c.order ?? 'canonical']}', palette),
          _line(
              Icons.check_circle_outline,
              previouslyRead.isEmpty
                  ? fill(u['previewChapters'], {'count': fmt.number(items.length)})
                  : fill(u['previewChaptersOpen'], {'count': fmt.number(open), 'read': fmt.number(previouslyRead.length)}),
              palette),
          if (result.days.isNotEmpty)
            _line(
                Icons.flag_outlined,
                fill(u['previewEnd'], {
                  'days': fmt.number(result.days.length),
                  'date': fmt.date(result.days.last.date, long: true),
                }),
                palette),
          Text(t.beginning, style: TextStyle(fontWeight: FontWeight.w700, color: palette.previewForeground)),
          for (final day in result.days.where((x) => !fixed || x.chapters.isNotEmpty).take(3))
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 34,
                child: Text('${day.index + 1}'.padLeft(2, '0'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: palette.previewMuted)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      passage(displayOrder(day.chapters, c), names).isEmpty
                          ? t.rest
                          : passage(displayOrder(day.chapters, c), names),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      if (fixed) '${bible52Text(lang).week} ${day.index ~/ 7 + 1} · ${u['cat${day.index % 7}']}'
                      else fmt.date(day.date),
                      if (day.words > 0) '${t.approx} ${fmt.time(estimatedSeconds(day.words, pace))}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: palette.previewMuted),
                  ),
                ]),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String value, Palette palette) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.previewMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      );
}

/// Full-screen picker for chapters read before the plan.
class _PreviousPage extends StatefulWidget {
  const _PreviousPage({required this.config, required this.value, required this.seconds, required this.lang});
  final Config config;
  final List<int> value;
  final int? seconds;
  final Lang lang;
  @override
  State<_PreviousPage> createState() => _PreviousPageState();
}

class _PreviousPageState extends State<_PreviousPage> {
  late List<int> value = [...widget.value];
  late int? seconds = widget.seconds;

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final p = planText(lang), t = text(lang), f = bible52Text(lang), u = ui(lang);
    final fixed = isBible52(widget.config);
    return Scaffold(
      appBar: AppBar(title: Text(u['readBefore'])),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Muted(fixed ? f.progressHelp : p.previousHelp),
          const SizedBox(height: 12),
          if (fixed)
            Bible52Weeks(value: value, lang: lang, onChanged: (x) => setState(() => value = x))
          else
            PreviousPicker(
                config: widget.config, value: value, lang: lang, onChanged: (x) => setState(() => value = x)),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 14),
            Panel(
              padding: const EdgeInsets.all(14),
              child: DurationFields(
                seconds: seconds,
                lang: lang,
                estimate: previousEstimate(widget.config, value, lang),
                onChanged: (s) => seconds = s,
              ),
            ),
          ],
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, (value, seconds)), child: Text(t.save))),
          ]),
        ),
      ),
    );
  }
}

/// Estimated time for chapters read before, at the default pace (for hints).
String previousEstimate(Config config, List<int> ids, Lang lang) {
  final set = ids.toSet();
  final chapters = [for (final c in scopeFor(config)) if (set.contains(c.id)) c];
  return readingTime(chaptersSeconds(chapters, readingPace(null)), lang);
}
