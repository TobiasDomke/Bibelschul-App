enum Lang { de, ru, en, uk }

const languageLabels = {
  Lang.de: 'Deutsch',
  Lang.ru: 'Русский',
  Lang.en: 'English',
  Lang.uk: 'Українська',
};

const locales = {
  Lang.de: 'de_DE',
  Lang.ru: 'ru_RU',
  Lang.en: 'en_GB',
  Lang.uk: 'uk_UA',
};

Lang? parseLang(Object? value) {
  for (final l in Lang.values) {
    if (l.name == value) return l;
  }
  return null;
}

bool isLanguage(Object? value) => parseLang(value) != null;

/// First language subtag of a locale such as "de-DE" or "uk_UA"; English otherwise.
Lang browserLanguage(String value) =>
    parseLang(value.toLowerCase().split(RegExp('[-_]')).first) ?? Lang.en;
