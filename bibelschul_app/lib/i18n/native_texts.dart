import '../core/languages.dart';

/// Texts that exist only in the native app (local reminders, share sheet).
/// Everything else comes unchanged from the web app (strings.g.dart).
class NativeTexts {
  final String reminderTitle;
  final String reminderIntro;
  final String reminderPrivacy;
  final String reminderBlocked;
  final String reminderSaved;
  final String testShown;
  final String shareFailed;
  final String importHelp;
  final String exportCsv;
  final String about;
  const NativeTexts({
    required this.reminderTitle,
    required this.reminderIntro,
    required this.reminderPrivacy,
    required this.reminderBlocked,
    required this.reminderSaved,
    required this.testShown,
    required this.shareFailed,
    required this.importHelp,
    required this.exportCsv,
    required this.about,
  });
}

const nativeTranslations = {
  Lang.de: NativeTexts(
    reminderTitle: 'Tägliche Erinnerung auf diesem Gerät',
    reminderIntro: 'Leseweg erinnert dich täglich zur gewählten Uhrzeit an das Lesen in deiner Papierbibel.',
    reminderPrivacy:
        'Die Erinnerung wird direkt auf diesem Gerät geplant und funktioniert auch ohne Internet. Es werden keine Daten an einen Dienst übertragen.',
    reminderBlocked:
        'Mitteilungen sind für Leseweg nicht erlaubt. Erlaube sie in den Systemeinstellungen und versuche es erneut.',
    reminderSaved: 'Erinnerung gespeichert.',
    testShown: 'Testnachricht angezeigt.',
    shareFailed: 'Die Datei konnte nicht geteilt werden.',
    importHelp: 'Auch Sicherungen aus der Leseweg-Web-App lassen sich hier importieren.',
    exportCsv: 'Statistik teilen (CSV)',
    about: 'Über Leseweg',
  ),
  Lang.ru: NativeTexts(
    reminderTitle: 'Ежедневное напоминание на этом устройстве',
    reminderIntro: 'Leseweg каждый день в выбранное время напоминает о чтении твоей печатной Библии.',
    reminderPrivacy:
        'Напоминание планируется прямо на этом устройстве и работает без интернета. Данные никуда не передаются.',
    reminderBlocked:
        'Уведомления для Leseweg не разрешены. Разреши их в настройках системы и попробуй ещё раз.',
    reminderSaved: 'Напоминание сохранено.',
    testShown: 'Проверочное уведомление показано.',
    shareFailed: 'Не удалось поделиться файлом.',
    importHelp: 'Здесь можно импортировать и резервные копии из веб-приложения Leseweg.',
    exportCsv: 'Поделиться статистикой (CSV)',
    about: 'О Leseweg',
  ),
  Lang.en: NativeTexts(
    reminderTitle: 'Daily reminder on this device',
    reminderIntro: 'Leseweg reminds you every day at your chosen time to read your paper Bible.',
    reminderPrivacy:
        'The reminder is scheduled directly on this device and works without internet. No data is sent to any service.',
    reminderBlocked: 'Notifications are not allowed for Leseweg. Allow them in the system settings and try again.',
    reminderSaved: 'Reminder saved.',
    testShown: 'Test notification shown.',
    shareFailed: 'The file could not be shared.',
    importHelp: 'Backups from the Leseweg web app can be imported here as well.',
    exportCsv: 'Share statistics (CSV)',
    about: 'About Leseweg',
  ),
  Lang.uk: NativeTexts(
    reminderTitle: 'Щоденне нагадування на цьому пристрої',
    reminderIntro: 'Leseweg щодня у вибраний час нагадує про читання твоєї паперової Біблії.',
    reminderPrivacy:
        'Нагадування плануються безпосередньо на цьому пристрої й працюють без інтернету. Дані нікуди не передаються.',
    reminderBlocked:
        'Сповіщення для Leseweg не дозволені. Дозволь їх у налаштуваннях системи й спробуй ще раз.',
    reminderSaved: 'Нагадування збережено.',
    testShown: 'Тестове сповіщення показано.',
    shareFailed: 'Не вдалося поділитися файлом.',
    importHelp: 'Тут також можна імпортувати резервні копії з вебзастосунку Leseweg.',
    exportCsv: 'Поділитися статистикою (CSV)',
    about: 'Про Leseweg',
  ),
};

NativeTexts nativeText(Lang lang) => nativeTranslations[lang]!;
