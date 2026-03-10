# Interne APK-Verteilung (empfohlen: Google Drive privat)

Stand: 2026-03-09

Ziel: Interne Tester sollen die APK sicher laden koennen, ohne Store-Release.

## Schritt 1: APK bauen

```bash
CUSTOMER_TOP_UP_ENABLED=false \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/build_android_internal_apk.sh
```

## Schritt 2: Testpaket erzeugen

```bash
/Users/fynn-olegottsch/glanzpunkt_app/scripts/package_internal_release_bundle.sh
```

Ergebnis liegt unter:

- `/Users/fynn-olegottsch/glanzpunkt_app/build/internal_release/<BUILD_TAG>/`

Enthaelt:

- `app-release.apk`
- `SHA256SUMS.txt`
- `RELEASE_NOTES.txt`
- `internal_tester_install_guide_de.md`

## Schritt 3: Google Drive Ordner vorbereiten

1. Drive-Ordner `Glanzpunkt-Internal-Tester` erstellen.
2. Unterordner pro Build-Tag anlegen.
3. Dateien aus `build/internal_release/<BUILD_TAG>/` hochladen.
4. Freigabe nur fuer konkrete Tester-E-Mails (kein oeffentlicher Link).

## Schritt 4: Tester-Handover senden

In die Nachricht an Tester:

- Download-Link
- SHA256-Pruefsumme aus `SHA256SUMS.txt`
- Kurzanleitung aus `internal_tester_install_guide_de.md`
- Support-Mail: `support@glanzpunkt-wahlstedt.de`

## Schritt 5: Nach dem Test

1. Feedback einsammeln.
2. Problematische Builds im Drive-Ordner als `deprecated` markieren.
3. Nur letzten stabilen Build als `current` kennzeichnen.

