import 'languages.dart';

const editionIds = ['schlachter2000', 'kjv', 'synodal', 'ohienko'];

class EditionInfo {
  final String name;
  final String order; // "western" | "eastern"
  final String source;
  const EditionInfo(this.name, this.order, this.source);
}

const Map<String, EditionInfo> editions = {
  'schlachter2000': EditionInfo('Schlachter 2000', 'western', 'https://www.schlachterbibel.de/de/bibel/'),
  'kjv': EditionInfo('King James Version', 'western', 'https://only.bible/bible/kjv/'),
  'synodal': EditionInfo('Синодальный перевод · 66 книг', 'eastern', 'https://only.bible/bible/rst66/'),
  'ohienko': EditionInfo('Іван Огієнко (1962)', 'eastern', 'https://only.bible/bible/ubio/'),
};

String languageEdition(Lang lang) =>
    const {Lang.de: 'schlachter2000', Lang.en: 'kjv', Lang.ru: 'synodal', Lang.uk: 'ohienko'}[lang]!;

String editionName(String? edition) => editions[edition ?? 'schlachter2000']!.name;

/// Content links to the independently checked Schlachter inventory. Fractions
/// approximate text weights only; every selected-edition chapter stays whole.
List<(int, double)> sourceParts(String edition, String code, int number) {
  if (edition != 'schlachter2000') {
    if (code == 'JOL') {
      return number == 1
          ? [(1, 1)]
          : number == 2
              ? [(2, 1), (3, 1)]
              : [(4, 1)];
    }
    if (code == 'MAL') {
      return number < 3
          ? [(number, 1)]
          : number == 3
              ? [(3, 510 / 686)]
              : [(3, 176 / 686)];
    }
  }
  if (edition == 'synodal' && code == 'PSA') {
    if (number <= 8 || number >= 148) return [(number, 1)];
    if (number == 9) return [(9, 1), (10, 1)];
    if (number <= 112) return [(number + 1, 1)];
    if (number == 113) return [(114, 1), (115, 1)];
    if (number == 114) return [(116, 9 / 19)];
    if (number == 115) return [(116, 10 / 19)];
    if (number <= 145) return [(number + 1, 1)];
    if (number == 146) return [(147, 11 / 20)];
    return [(147, 9 / 20)];
  }
  return [(number, 1)];
}
