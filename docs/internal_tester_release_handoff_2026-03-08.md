# Internal Tester Release Handoff (2026-03-08)

## Build Identity

- App version: `1.0.2+3`
- Channel: `internal`
- Backend mode: `USE_MOCK_BACKEND=false`
- Customer top-up flag: `CUSTOMER_TOP_UP_ENABLED=false`

## Artifact

- APK path:
  `/Users/fynn-olegottsch/glanzpunkt_app/artifacts/internal-test/glanzpunkt_app-1.0.2+3-internal.apk`
- SHA256 file:
  `/Users/fynn-olegottsch/glanzpunkt_app/artifacts/internal-test/glanzpunkt_app-1.0.2+3-internal.apk.sha256`
- SHA256:
  `bbe290bf44c23373801616ec1c9b55169b81dca20e63dd43f73ca792fee43ba4`
- Size (bytes):
  `70982448`

## Tester Checklist

1. APK nur aus dem freigegebenen Link laden.
2. SHA256 gegen bereitgestellte `.sha256` Datei prüfen.
3. Installation auf Android-Gerät durchführen.
4. Kernflows testen:
   - Login/Gast
   - Box reservieren/starten/stoppen
   - Wallet + Historie
   - Loyalty + Reward
   - Operator-Zugriffsschutz
5. Feedback mit Angabe von:
   - Gerät + Android-Version
   - App-Version `1.0.2+3`
   - Uhrzeit + Screenshot + Repro-Schritte

## Copy/Paste Versandtext (Tester)

```text
Neue interne Testversion ist verfügbar.

Version: 1.0.2+3 (internal)
Datei: glanzpunkt_app-1.0.2+3-internal.apk
SHA256: bbe290bf44c23373801616ec1c9b55169b81dca20e63dd43f73ca792fee43ba4

Bitte vor Installation den Hash prüfen.
Danach die Kernflows testen (Login/Gast, Reserve/Activate/Stop, Wallet, Loyalty).
Fehler bitte mit Screenshot, Uhrzeit und Repro-Schritten melden.
```
