import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/languages.dart';
import '../core/state.dart';
import '../core/util.dart';
import '../i18n/app_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/feature_texts.dart';
import 'notes_ui.dart';
import 'plan_tab.dart';
import 'planner_form.dart';
import 'settings_tab.dart';
import 'small_parts.dart';
import 'stats_tab.dart';
import 'theme.dart';
import 'today_tab.dart';
import 'widgets.dart';

/// App shell: header, status messages and the four tabs (app/leseweg.tsx).
class Home extends StatelessWidget {
  const Home({super.key, required this.c});
  final AppController c;

  static const _tabs = ['today', 'plan', 'notes', 'stats', 'settings'];

  @override
  Widget build(BuildContext context) {
    final lang = c.lang;
    final t = text(lang);
    final palette = context.palette;
    final v = PlanView.of(c);
    final showTabs = c.status == LoadStatus.ready && c.state != null && !c.newPlan;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.menu_book, size: 20, color: palette.onPrimary),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Leseweg', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(t.tagline,
                  style: TextStyle(fontSize: 10, letterSpacing: 1, color: palette.mutedForeground),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        // The language matters most before a plan exists; afterwards it lives in the settings.
        actions: [
          if (!showTabs)
            PopupMenuButton<Lang>(
              tooltip: t.language,
              enabled: !c.busy && c.status == LoadStatus.ready,
              initialValue: lang,
              onSelected: c.changeLanguage,
              itemBuilder: (_) => [
                for (final l in Lang.values) PopupMenuItem(value: l, child: Text(languageLabels[l]!)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.language, size: 20),
                  const SizedBox(width: 4),
                  Text(lang.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ],
      ),
      bottomNavigationBar: showTabs
          ? NavigationBar(
              selectedIndex: _tabs.indexOf(c.tab),
              onDestinationSelected: (i) => c.setTab(_tabs[i]),
              destinations: [
                NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), label: t.today),
                NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), label: t.plan),
                NavigationDestination(icon: const Icon(Icons.edit_note), label: featureText(lang)['notes']),
                NavigationDestination(icon: const Icon(Icons.bar_chart), label: t.stats),
                NavigationDestination(icon: const Icon(Icons.settings_outlined), label: t.settings),
              ],
            )
          : null,
      body: SafeArea(
        bottom: !showTabs,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: ValueKey('${c.tab}-${c.newPlan}-${c.state == null}-${c.selected}'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                ..._banners(context, v),
                _body(context, v),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.eco_outlined, size: 16, color: palette.mutedForeground),
                  const SizedBox(width: 6),
                  Flexible(child: Muted(t.footer, size: 12.5)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _banners(BuildContext context, PlanView? v) {
    final lang = c.lang;
    final t = text(lang), f = bible52Text(lang), deadline = deadlineText(lang);
    final s = c.state;
    final fixed = v?.fixed ?? false;
    final out = <Widget>[];
    void add(Widget w) => out.addAll([w, const SizedBox(height: 12)]);
    if (s != null && s.chapterCorrection != null) add(ChapterCorrectionNotice(state: s, lang: lang));
    if (s?.pendingBookOrder != null) add(Notice(text: bookOrderText(lang).pending));
    if (c.error.isNotEmpty) {
      add(Notice(
        kind: NoticeKind.error,
        text: c.error == 'timer' ? (fixed ? f.open : t.busyTimer) : (c.error == 'changed' ? t.planChanged : t.error),
        actions: [
          if (c.error == 'timer' && (s?.timer != null || (fixed && s?.pace?.draft != null)))
            TextButton(
              onPressed: () => c.choose(s?.timer?.day ?? s?.pace?.draft?.day ?? v?.dateIndex ?? 0),
              child: Text(t.goTimer),
            ),
        ],
      ));
    }
    if (c.message.isNotEmpty && v != null) {
      final id = c.message;
      final text = switch (id) {
        'deadline' => deadline.saved,
        'note' => featureText(lang)['noteSaved'],
        'noteDeleted' => featureText(lang)['noteDeleted'],
        'saved' => t.saved,
        'replanned' => [
            c.moved.isEmpty
                ? ui(lang)['savedNice']
                : fill(ui(lang)['moved'], {'count': c.moved.length, 'passage': v.readLabel(c.moved)}),
            if (v.remainingDays > 0 && v.remainingChapters > 0)
              fill(ui(lang)['perDayNow'],
                  {'time': Fmt(lang).time(v.pace.secondsPerWord * v.remainingWords / v.remainingDays)}),
          ].join(' '),
        _ => t.timerStopped,
      };
      // A snack bar is visible wherever the reader has scrolled to.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (c.message != id || !context.mounted) return;
        c.message = '';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6), showCloseIcon: true));
      });
    }
    return out;
  }

  Widget _body(BuildContext context, PlanView? v) {
    final lang = c.lang;
    final t = text(lang);
    if (c.status == LoadStatus.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(t.loading)]),
      );
    }
    if (c.status == LoadStatus.error) {
      return Panel(
        child: Gap(children: [
          Text(t.unavailable),
          OutlinedButton(onPressed: () => c.load(), child: Text(t.retry)),
        ]),
      );
    }
    if (c.state == null || c.newPlan) {
      final u = ui(lang);
      return Gap(space: 16, children: [
        if (c.newPlan)
          Row(children: [
            Expanded(child: Heading(u['newPlanTitle'], size: 26)),
            TextButton.icon(
              onPressed: () => c.update(() => c.newPlan = false),
              icon: const Icon(Icons.close, size: 18),
              label: Text(t.cancel),
            ),
          ])
        else ...[
          Heading(t.title, size: 28),
          Muted(u['introText'], size: 15),
        ],
        PlannerForm(
          key: ValueKey(lang),
          lang: lang,
          busy: c.busy,
          zone: c.deviceZone,
          onSave: (choice) async {
            final s = await c.mutate({
              'action': 'create',
              'config': choice.config.toJson(),
              'previouslyRead': choice.previouslyRead,
              'lang': lang.name,
            });
            if (s != null) {
              c.update(() {
                c.newPlan = false;
                c.selected = null;
                c.page = 0;
                c.tab = 'today';
                c.reminderTime = s.config.time;
                c.zone = s.config.timezone;
              });
              if (choice.remind) await c.enableReminders();
            }
          },
        ),
        if (c.state == null) ExistingPlanCard(c: c),
      ]);
    }
    return switch (c.tab) {
      'plan' => PlanTab(c: c, v: v!),
      'notes' => NotesTab(c: c),
      'stats' => StatsTab(c: c, v: v!),
      'settings' => SettingsTab(c: c, v: v!),
      _ => TodayTab(c: c, v: v!),
    };
  }
}

/// Keeps the "today" ISO date consistent in places without a PlanView.
String todayFor(ReadingState? s) => today(s?.config.timezone ?? 'Europe/Berlin');
