import 'languages.dart';

// These describe book order, not a translation or a different biblical canon.
// Chapter IDs and chapter numbering always stay independent of display order.
const bookOrders = ['western', 'eastern'];

String languageBookOrder(Lang lang) => lang == Lang.ru || lang == Lang.uk ? 'eastern' : 'western';

const _oldTestament =
    'GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL';
const _gospelsActs = 'MAT MRK LUK JHN ACT';
const _paul = 'ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB';
const _general = 'JAS 1PE 2PE 1JN 2JN 3JN JUD';

final Map<String, List<String>> bookSequences = {
  'western': '$_oldTestament $_gospelsActs $_paul $_general REV'.split(' '),
  'eastern': '$_oldTestament $_gospelsActs $_general $_paul REV'.split(' '),
};

final Map<String, Map<String, int>> _positions = {
  for (final order in bookOrders)
    order: {for (final (i, code) in bookSequences[order]!.indexed) code: i},
};

List<T> sortByBookOrder<T>(List<T> items, String? order, String Function(T) code, int Function(T) number) {
  final rank = _positions[order ?? 'western']!;
  // Dart's List.sort is not stable; break ties by original index like JS stable sort.
  final indexed = [for (final (i, item) in items.indexed) (i, item)];
  indexed.sort((a, b) {
    final c = rank[code(a.$2)]! - rank[code(b.$2)]!;
    if (c != 0) return c;
    final n = number(a.$2) - number(b.$2);
    return n != 0 ? n : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// "auto" | "western" | "eastern"
String bookOrderChoice({String? bookOrder, String? bookOrderMode}) =>
    bookOrderMode == 'auto' ? 'auto' : (bookOrder ?? 'western');
