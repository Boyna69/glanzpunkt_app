# Interne Tester-Installationsanleitung (APK + iPhone lokal)

Stand: 2026-03-09

Diese Anleitung ist fuer interne Tester ohne Store-Release gedacht.

## 1) Android-Installation (APK)

### Voraussetzungen

- Android-Smartphone (idealerweise Android 10+).
- Zugang zu einem privaten Download-Link fuer `app-release.apk`.

### Installation

1. APK herunterladen (nicht umbenennen).
2. In Android `Einstellungen` -> `Sicherheit` (oder `Apps`) Installationen aus dieser Quelle erlauben.
3. APK im Download-Ordner antippen.
4. `Installieren` bestaetigen.
5. App starten und Login testen.

### Update auf neue Testversion

1. Neue APK herunterladen.
2. Alte App nicht manuell deinstallieren (damit Daten erhalten bleiben).
3. Neue APK installieren (Update ueber bestehende Version).

### Rollback bei Problemen

1. App deinstallieren.
2. Vorherige APK-Version installieren.
3. Fehler mit Screenshot + Uhrzeit melden.

## 2) iPhone-Installation (lokal ueber Xcode, ohne TestFlight)

### Voraussetzungen

- Mac mit Xcode.
- iPhone per Kabel verbunden.
- Entwickler-Modus am iPhone aktiv.

### Installation

1. Im Projektordner auf dem Mac ausfuehren:

```bash
flutter run --release -d "<iPhone-Name>" \
  --dart-define=USE_MOCK_BACKEND=false \
  --dart-define=SUPABASE_URL=https://ucnvzrpcjkpaltuylvbv.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<DEIN_PUBLISHABLE_KEY>
```

2. App startet auf dem iPhone.
3. Falls iOS eine Warnung zeigt:
   `Einstellungen` -> `Allgemein` -> `VPN & Geraetemanagement` -> Entwicklerzertifikat vertrauen.

### Wichtige Einschraenkung

- Ohne Apple-Developer-Abo ist dies nur lokales Testing und zeitlich begrenzt.
- Fuer breites iOS-Testing ist spaeter TestFlight notwendig.

## 3) Bug-Meldung Standard (fuer alle Tester)

Bitte jede Meldung mit diesen Angaben schicken:

- Geraet + OS-Version
- App-Version / Build
- Exakte Schritte
- Erwartetes Verhalten
- Tatsaechliches Verhalten
- Screenshot oder Screen-Recording
- Zeitpunkt (Datum/Uhrzeit)

