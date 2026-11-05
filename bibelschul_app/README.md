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
| `test/features_test.dart` | Notizen in Sicherungen, Plan-Codes, Erinnerungsregeln, Rückstand, automatische Sicherung, Übersetzungen |

## Funktionen nur in der App

- **Heute**: „Alles gelesen“ mit einem Tipp, Abschließen ohne zweiten Dialog (nur eine ungewöhnliche Messung fragt nach), Fragen zum Nachdenken passend zur Textgattung, eine Notiz pro Leseeinheit und ein Hinweis mit „Ziel verschieben“, wenn man deutlich hinter dem ursprünglichen Plan liegt. Erklärtexte stehen unter „⋯ › So funktioniert es“ und in Einstellungen › Hinweise.
- **Notizen**: eigener Tab mit Suche und Export als Text.
- **Statistik**: Bücher-Übersicht mit einer Kachel je Buch.
- **Einrichtung**: Vorlagen zum Schnellstart (ganze Bibel, NT in 90 Tagen, chronologisch, abwechslungsreich, Bibelleseplan 52).
- **Erinnerungen**: pro Tag geplant; an Tagen mit gelesenem Abschnitt entfällt die Erinnerung, optional zweite Erinnerung am Abend.
- **Plan teilen**: QR-Code oder Text-Code mit den Planeinstellungen für Klassen und Gruppen; „Plan einer Gruppe übernehmen“ per Kamera oder Einfügen.
- **Automatische Sicherung**: nach jeder Leseeinheit eine Datei pro Tag (die letzten 10) im Dokumente-Ordner, auf dem iPhone in der Dateien-App sichtbar.
- **iPhone-Widget** (Startbildschirm und Sperrbildschirm) mit den heutigen Kapiteln und dem Fortschritt sowie **Live Activity**: Der laufende Timer erscheint auf dem Sperrbildschirm und in der Dynamic Island. Code: `ios/LesewegWidget/`, `ios/Shared/`, `ios/Runner/NativeBridge.swift`; das Xcode-Ziel legt `tool/add_widget_target.rb` an.

Sicherungen ohne Notizen bleiben Format 8 und damit in der Web-App ladbar; mit Notizen verwendet die App Format 9.

## Unterschiede zur Web-App

- **Erinnerungen** werden lokal auf dem Gerät geplant (keine Cloudflare-Push-Anmeldung, funktioniert offline).
- **Sicherung und CSV** gehen über das Teilen-Menü des Systems; der Import nimmt auch Sicherungen der Web-App an. Der Kalender-Export (.ics) entfällt, weil er nach jeder Planänderung veraltete; die Erinnerungen übernehmen diese Aufgabe.
- Die Liste zur Prüfung einzelner Zeitmessungen entfällt; die automatische Ausreißer-Erkennung bleibt.
- **Installation, Offline-Cache und App-Updates** entfallen; Updates kommen über App Store / Google Play.
- Daten liegen in der App-Sandbox. Der Umzug aus der Web-App erfolgt über *Sicherung herunterladen* → *Sicherung laden*.

## Entwickeln

Voraussetzungen: Flutter 3.47+, für iOS Xcode, für Android das Android SDK.

Für Widget und App-Gruppe auf einem echten iPhone in Xcode unter *Signing & Capabilities* für die Ziele „Runner“ und „LesewegWidget“ das eigene Team wählen; die App-Gruppe `group.de.bibelschulapp.leseweg` legt Xcode dann automatisch an.

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
