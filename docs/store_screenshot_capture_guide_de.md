# Store Screenshot Capture Guide (DE)

Stand: 2026-03-10

Ziel: Einheitliche, reproduzierbare Screenshots fuer Play Store und App Store.

## 1) Allgemeine Regeln

- Keine Debug-Banner, keine Dev-Overlays.
- Einheitliche Sprache (DE) und konsistente Testdaten.
- Keine personenbezogenen echten Kundendaten sichtbar.
- Fuer jede Ansicht 1-2 saubere Screenshots.

## 2) Android Screenshots

### Option A: Direkt am Geraet

1. App in den Zielscreen navigieren.
2. Screenshot mit Hardware-Tastenkombi aufnehmen.
3. Dateien sammeln und klar benennen (z. B. `01_login_guest_android.png`).

### Option B: Emulator/ADB

```bash
adb devices
adb exec-out screencap -p > 01_login_guest_android.png
```

## 3) iOS Screenshots

### Option A: iPhone

1. Zielscreen oeffnen.
2. Screenshot mit iPhone-Tastenkombi aufnehmen.
3. AirDrop/Dateien-App zum Mac.

### Option B: iOS Simulator

1. Zielscreen im Simulator oeffnen.
2. `File` -> `Save Screen Shot` (oder Cmd+S).

## 4) Empfohlene Reihenfolge (gleich zu Draft)

1. Login mit Gastmodus
2. Home mit Live-Boxstatus
3. Waschstart-Flow
4. Loyalty/Reward
5. Wallet/Buchungen
6. Operator-Dashboard (nur falls in gleicher App fuer Store sichtbar)

## 5) Dateibenennung

- `01_login_guest.png`
- `02_home_live_boxes.png`
- `03_start_flow.png`
- `04_loyalty_reward.png`
- `05_wallet_history.png`
- `06_operator_dashboard.png`

## 6) Optional: Screenshot-Pack automatisiert vorbereiten

Initiales Pack mit Pflicht-Dateinamen erzeugen:

```bash
/Users/fynn-olegottsch/glanzpunkt_app/scripts/init_store_screenshot_pack.sh
```

Pack validieren (zeigt fehlende Dateien):

```bash
/Users/fynn-olegottsch/glanzpunkt_app/scripts/validate_store_screenshot_pack.sh \
  /Users/fynn-olegottsch/glanzpunkt_app/build/store_assets/<PACK_TAG>
```
