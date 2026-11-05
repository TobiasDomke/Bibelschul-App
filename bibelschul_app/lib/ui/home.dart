import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/languages.dart';
import '../core/state.dart';
import '../core/util.dart';
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
        actions: [
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
    final t = text(lang), p = planText(lang), f = bible52Text(lang), deadline = deadlineText(lang);
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
      final text = switch (c.message) {
        'deadline' => deadline.saved,
        'note' => featureText(lang)['noteSaved'],
        'noteDeleted' => featureText(lang)['noteDeleted'],
        'saved' => t.saved,
        'replanned' => t.replanned +
            (v.remainingDays > 0 && v.remainingChapters > 0
                ? ' ${fill(p.workload, {'time': Fmt(lang).time(v.pace.secondsPerWord * v.remainingWords / v.remainingDays)})}'
                : ''),
        _ => t.timerStopped,
      };
      add(Notice(text: text));
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
      return Gap(space: 16, children: [
        Eyebrow(t.eyebrow),
        Heading(t.title, size: 28),
        Text(t.subtitle, style: TextStyle(fontSize: 16, color: context.palette.foreground)),
        Muted(t.localIntro),
        if (c.newPlan)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => c.update(() => c.newPlan = false),
            icon: const Icon(Icons.close, size: 16),
            label: Text(t.cancel),
          ),
        PlannerForm(
          key: ValueKey(lang),
          lang: lang,
          busy: c.busy,
          zone: c.deviceZone,
          onSave: (Config config, List<int> previouslyRead) async {
            final s = await c.mutate({
              'action': 'create',
              'config': config.toJson(),
              'previouslyRead': previouslyRead,
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
            }
          },
        ),
        if (c.state == null) ...[BackupCard(c: c), JoinPlanCard(c: c)],
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
