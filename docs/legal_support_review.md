# Legal and Support Review (Pre-Store)

Stand: 2026-03-08

Ziel: finaler Check fuer Punkt "Rechtliches & Support" vor Store-Submission.

## 1) In-App Werte (Soll)

- Datenschutz URL: `https://www.glanzpunkt-wahlstedt.de/datenschutz`
- Impressum URL: `https://www.glanzpunkt-wahlstedt.de/impressum`
- Support E-Mail: `support@glanzpunkt-wahlstedt.de`

## 2) Quick Verify in Code

- `lib/core/app_config.dart`
  - `legalPrivacyUrl`
  - `legalImprintUrl`
  - `supportEmail`
- `lib/screens/settings_screen.dart`
  - Bereich "Rechtliches & Support"

## 3) Produktive Abnahme (manuell)

- Datenschutz-Link oeffnet korrekt und liefert HTTP 200.
- Impressum-Link oeffnet korrekt und liefert HTTP 200.
- Support-Mailadresse ist klickbar und korrekt vorbelegt.
- Keine alten Domains/E-Mails mehr in der App sichtbar.
- Texte sind mit finalem Unternehmensauftritt abgestimmt.

## 4) Evidence fuer Release

- 2 Screenshots:
  - Settings -> Datenschutz/Impressum
  - Settings -> Support
- Optional Log:
  - Terminal: `curl -I https://www.glanzpunkt-wahlstedt.de/datenschutz`
  - Terminal: `curl -I https://www.glanzpunkt-wahlstedt.de/impressum`
  - Script: `RUN_LEGAL_SUPPORT_CHECK=1 /Users/fynn-olegottsch/glanzpunkt_app/scripts/release_smoke.sh`

## 5) Sign-off

- Verantwortlich:
- Datum:
- Ergebnis: `PASS` / `FAIL`

## 6) Letzte Live-Pruefung (2026-03-08)

- `https://www.glanzpunkt-wahlstedt.de/datenschutz` -> Redirect auf
  `https://glanzpunkt-wahlstedt.de/datenschutz/` -> final `200`
- `https://www.glanzpunkt-wahlstedt.de/impressum` -> Redirect auf
  `https://glanzpunkt-wahlstedt.de/impressum/` -> final `200`

Aktueller Stand: `PASS`.

## 7) Root-Cause Snapshot (historisch, 2026-03-06)

- Live-Pruefung zeigt weiter `404` fuer Datenschutz/Impressum.
- `wp-json` Seitenliste liefert aktuell nur:
  - `https://glanzpunkt-wahlstedt.de/` (Homepage)
  - `https://glanzpunkt-wahlstedt.de/sample-page/`
- Fazit: die rechtlichen Zielseiten sind sehr wahrscheinlich noch nicht angelegt
  oder unter anderen Slugs veroeffentlicht.

Konkrete To-dos im CMS:

1. Seite mit Slug `datenschutz` erstellen/veroeffentlichen.
2. Seite mit Slug `impressum` erstellen/veroeffentlichen.
3. Danach Smoke-Check laufen lassen:
   `RUN_LEGAL_SUPPORT_CHECK=1 /Users/fynn-olegottsch/glanzpunkt_app/scripts/release_smoke.sh`
