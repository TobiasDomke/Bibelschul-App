import 'package:flutter/material.dart';

import '../core/book_order.dart';
import '../core/data.g.dart';
import '../core/languages.dart';
import '../core/planner.dart';
import '../core/state.dart';
import '../i18n/i18n.dart';
import 'widgets.dart';

/// Book order of the reader's printed Bible (app/book-order-control.tsx).
class BookOrderControl extends StatelessWidget {
  const BookOrderControl({
    super.key,
    required this.config,
    required this.lang,
    required this.onChanged,
    this.disabled = false,
    this.pending,
  });
  final Config config;
  final Lang lang;
  final ValueChanged<String> onChanged;
  final bool disabled;
  final String? pending;

  @override
  Widget build(BuildContext context) {
    final t = bookOrderText(lang);
    final names = bookNames(lang);
    final selected = pending ?? config.bookOrder ?? 'western';
    final indices = <int>{
      for (final c in scopeChapters(scope: config.scope, bookOrder: selected, edition: config.edition)) c.bookIndex,
    };
    return Gap(children: [
      LabeledDropdown<String>(
        label: t.title,
        value: bookOrderChoice(bookOrder: selected, bookOrderMode: config.bookOrderMode),
        enabled: !disabled,
        items: [('auto', t.auto), ('western', t.western), ('eastern', t.eastern)],
        onChanged: onChanged,
      ),
      FinePrint(t.help),
      Text.rich(TextSpan(children: [
        TextSpan(text: '${t.applied} ', style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: t[selected]),
      ]), style: const TextStyle(fontSize: 12.5)),
      if (pending != null) Notice(text: t.pending),
      Details(summary: t.preview, children: [
        Text(indices.map((i) => names?[i] ?? bibleBooks[i].name).join(' → ')),
        Muted(t.planning),
      ]),
      FinePrint(experienceText(lang).editionHelp),
    ]);
  }
}
