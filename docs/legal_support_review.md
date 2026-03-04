# Legal and Support Review (Pre-Store)

Stand: 2026-03-01

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

## 5) Sign-off

- Verantwortlich:
- Datum:
- Ergebnis: `PASS` / `FAIL`

## 6) Letzte Live-Pruefung (2026-03-04)

- `https://www.glanzpunkt-wahlstedt.de/datenschutz` -> Redirect auf
  `https://glanzpunkt-wahlstedt.de/datenschutz` -> final `404`
- `https://www.glanzpunkt-wahlstedt.de/impressum` -> Redirect auf
  `https://glanzpunkt-wahlstedt.de/impressum` -> final `404`

Aktueller Stand: `FAIL` (Release-Blocker bis die Zielseiten live 200 liefern).
