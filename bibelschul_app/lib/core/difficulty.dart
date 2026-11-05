// How demanding a chapter is to read, beyond its length.
//
// Word counts alone treat a genealogy, a law code, a psalm and a letter of
// Paul alike. Readers of a printed Bible do not: lists of names are skimmed,
// stories flow, poetry, prophecy and dense letters take longer per word.
// Each chapter therefore gets a reading "effort" = words × factor of its kind.
// Plans are balanced by effort (equal time per day rather than equal words),
// and reading time is estimated per effort unit. The factors are deliberately
// moderate starting values; the measured sessions of each reader correct them
// per kind of text (see pace.dart).

/// Kinds of text with their starting factor (seconds per word relative to a story).
const Map<String, double> textKindFactors = {
  'narrative': 1.0,
  'gospel': 1.0,
  'law': 1.1,
  'list': 0.8,
  'poetry': 1.2,
  'wisdom': 1.25,
  'prophecy': 1.2,
  'letter': 1.25,
  'apocalyptic': 1.2,
};

/// Average pace for attentive reading of a printed Bible, in effort units per
/// minute. 130 × the average factor (≈ 1.08) is about 120 words per minute,
/// which puts the whole Bible at roughly 95–100 hours – a common estimate for
/// careful reading (fluent silent reading of easy German prose is ~180 wpm).
const double defaultEffortPerMinute = 130;

/// For the web-parity tests only: plain word counts and the web app's 180 wpm.
bool legacyReadingModel = false;

const _base = {
  'GEN': 'narrative', 'EXO': 'narrative', 'LEV': 'law', 'NUM': 'law', 'DEU': 'law', //
  'JOS': 'narrative', 'JDG': 'narrative', 'RUT': 'narrative', '1SA': 'narrative', '2SA': 'narrative',
  '1KI': 'narrative', '2KI': 'narrative', '1CH': 'narrative', '2CH': 'narrative', 'EZR': 'narrative',
  'NEH': 'narrative', 'EST': 'narrative', 'JOB': 'poetry', 'PSA': 'poetry', 'PRO': 'wisdom', 'ECC': 'wisdom',
  'SNG': 'poetry', 'ISA': 'prophecy', 'JER': 'prophecy', 'LAM': 'poetry', 'EZK': 'prophecy', 'DAN': 'prophecy',
  'HOS': 'prophecy', 'JOL': 'prophecy', 'AMO': 'prophecy', 'OBA': 'prophecy', 'JON': 'narrative', 'MIC': 'prophecy',
  'NAM': 'prophecy', 'HAB': 'prophecy', 'ZEP': 'prophecy', 'HAG': 'prophecy', 'ZEC': 'prophecy', 'MAL': 'prophecy',
  'MAT': 'gospel', 'MRK': 'gospel', 'LUK': 'gospel', 'JHN': 'gospel', 'ACT': 'narrative', 'REV': 'apocalyptic',
};

/// Chapters whose kind differs from their book's (chapter ranges are inclusive).
const _exceptions = <String, List<(String, List<(int, int)>)>>{
  'GEN': [('list', [(5, 5), (10, 10), (36, 36)])],
  'EXO': [('law', [(20, 23), (25, 31), (35, 40)])],
  'LEV': [('narrative', [(8, 10)])],
  'NUM': [
    ('list', [(1, 4), (7, 7), (26, 26), (33, 34)]),
    ('narrative', [(10, 14), (16, 17), (20, 25), (31, 32)]),
  ],
  'DEU': [('poetry', [(32, 33)]), ('narrative', [(34, 34)])],
  'JOS': [('list', [(13, 21)])],
  '2SA': [('poetry', [(22, 22)])],
  '1CH': [('list', [(1, 9), (23, 27)])],
  'EZR': [('list', [(2, 2)])],
  'NEH': [('list', [(3, 3), (7, 7), (10, 12)])],
  'JOB': [('narrative', [(1, 2)])],
  'ISA': [('narrative', [(36, 39)])],
  'JER': [('narrative', [(37, 45), (52, 52)])],
  'EZK': [('law', [(40, 48)])],
  'DAN': [('narrative', [(1, 6)]), ('apocalyptic', [(7, 12)])],
  'REV': [('letter', [(2, 3)])],
};

/// Kind of text of chapter [number] in the book with [code].
String textKind(String code, int number) {
  for (final (kind, ranges) in _exceptions[code] ?? const <(String, List<(int, int)>)>[]) {
    if (ranges.any((r) => number >= r.$1 && number <= r.$2)) return kind;
  }
  return _base[code] ?? 'letter';
}

/// Reading effort of a chapter: its words weighted by the kind of text.
int chapterEffort(String code, int number, int words) {
  if (legacyReadingModel) return words;
  final effort = (words * textKindFactors[textKind(code, number)]!).round();
  return effort < 1 ? 1 : effort;
}

/// Seconds per effort unit before any measurement.
double get defaultSecondsPerEffort => legacyReadingModel ? 60 / 180 : 60 / defaultEffortPerMinute;
