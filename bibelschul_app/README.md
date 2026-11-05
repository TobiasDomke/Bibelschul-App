# Bibelschul-App (Flutter)

Native App für **iOS (iPhone, iPad) und Android (Smartphones, Tablets)** mit
demselben Funktionsumfang wie die Leseweg-Web-App im Hauptverzeichnis. Ein
Code in Dart/Flutter für beide Plattformen. In der App heißt sie weiterhin
„Leseweg“.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `lib/core/` | 1:1-Übertragung von `../lib/*.ts`: Planer, Tagesverteilung, Aktionen, Lesetempo, Zieldatum, Lesezeit, Migrationen, Sicherung, CSV/Kalender |
| `lib/core/data.g.dart` | Wortzahlen, Kapitelinventare, Bibelleseplan 52 – erzeugt aus `../lib/*.json` |
| `lib/i18n/strings.g.dart` | alle Texte in Deutsch, Russisch, Englisch, Ukrainisch – erzeugt aus `../lib/*-i18n.ts` |
| `lib/i18n/native_texts.dart` | Texte nur für die App (lokale Erinnerungen, Teilen) |
| `lib/services/` | Speicherung (JSON-Datei, atomar), Einstellungen, lokale Erinnerungen, Teilen/Import |
| `lib/ui/` | Oberfläche: Heute, Leseplan, Statistik, Einstellungen, Einrichtung, Dialoge |
| `test/parity_test.dart` | Vergleich mit Referenzergebnissen der Web-App |
| `test/app_test.dart` | bedient die Oberfläche und erzeugt Bildschirmfotos (`test/goldens/`) |

## Unterschiede zur Web-App

- **Erinnerungen** werden lokal auf dem Gerät geplant (keine Cloudflare-Push-Anmeldung, funktioniert offline).
- **Sicherung, CSV, Kalender** gehen über das Teilen-Menü des Systems; der Import nimmt auch Sicherungen der Web-App an (gleiches Format 8).
- **Installation, Offline-Cache und App-Updates** entfallen; Updates kommen über App Store / Google Play.
- Daten liegen in der App-Sandbox. Der Umzug aus der Web-App erfolgt über *Sicherung herunterladen* → *Sicherung laden*.

## Entwickeln

Voraussetzungen: Flutter 3.47+, für iOS Xcode und CocoaPods, für Android das Android SDK.

```sh
flutter pub get
flutter test                      # Logik- und Oberflächentests
flutter run                       # auf Simulator/Emulator/Gerät
flutter build ios --no-codesign   # iOS-Build ohne Signierung
flutter build appbundle           # Android-Paket für Google Play
```

`test/parity_test.dart` braucht die Referenzdatei (44 MB, nicht im Repository).
Im Hauptverzeichnis erzeugen:

```sh
npm ci
node scripts/flutter/export-fixtures.mjs
```

Nach Änderungen an den Daten oder Texten der Web-App die generierten Dateien erneuern:

```sh
python3 scripts/flutter/export_data.py
node scripts/flutter/export-i18n.mjs
```

Bildschirmfotos aktualisieren: `flutter test test/app_test.dart --update-goldens`.
