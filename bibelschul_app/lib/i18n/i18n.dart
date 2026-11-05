import '../core/languages.dart';
import 'strings.g.dart';

export 'strings.g.dart';

MainTexts text(Lang lang) => mainTranslations[lang]!;
PlanTexts planText(Lang lang) => planTranslations[lang]!;
ExperienceTexts experienceText(Lang lang) => experienceTranslations[lang]!;
Bible52Texts bible52Text(Lang lang) => bible52Translations[lang]!;
BookOrderTexts bookOrderText(Lang lang) => bookOrderTranslations[lang]!;
ChapterCorrectionTexts chapterCorrectionText(Lang lang) => chapterCorrectionTranslations[lang]!;
DeadlineTexts deadlineText(Lang lang) => deadlineTranslations[lang]!;
ReadingTimeTexts readingTimeText(Lang lang) => readingTimeTranslations[lang]!;
PushTexts pushText(Lang lang) => pushTranslations[lang]!;

/// Translated book names, or null for German (the data file's names are German).
List<String>? bookNames(Lang lang) => bookNameTranslations[lang];

String bible52Position(int index, Lang lang) =>
    '${bible52Text(lang).week} ${index ~/ 7 + 1} · ${bible52Text(lang).unit} ${index % 7 + 1}/7';
