# Internal Tester Release Handoff (2026-03-10)

## Build Identity

- App version: `1.0.2+3`
- Channel: `internal`
- Backend mode: `USE_MOCK_BACKEND=false`
- Customer top-up flag: `CUSTOMER_TOP_UP_ENABLED=false`

## Artifact Bundle

- Bundle path:
  `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924`
- Evidence template:
  `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/DRY_RUN_EVIDENCE_TEMPLATE.md`

## Android Artifacts

- AAB path:
  `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/app-release.aab`
- AAB SHA256:
  `527b8bd3e2877e17874b535668638d8a24df0990a341db23ada625d142f8b326`
- AAB size (bytes):
  `53228558`

- APK path:
  `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/app-release.apk`
- APK SHA256:
  `bbe290bf44c23373801616ec1c9b55169b81dca20e63dd43f73ca792fee43ba4`
- APK size (bytes):
  `70982448`

## Included Docs

- `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/store_upload_dry_run_checklist.md`
- `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/store_metadata_release_draft_de.md`
- `/Users/fynn-olegottsch/glanzpunkt_app/build/store_dry_run/20260310-203924/store_screenshot_capture_guide_de.md`

## Tester Checklist

1. APK nur aus dem freigegebenen internen Link laden.
2. SHA256 gegen `SHA256SUMS.txt` pruefen.
3. Installation auf Android-Geraet durchfuehren.
4. Kernflows testen:
   - Login/Gast
   - Box reservieren/starten/stoppen
   - Wallet + Historie
   - Loyalty + Reward
   - Operator-Zugriffsschutz
5. Feedback mit:
   - Geraet + OS-Version
   - App-Version `1.0.2+3`
   - Uhrzeit + Screenshot + Repro-Schritte

## Copy/Paste Versandtext (Tester)

```text
Neue interne Testversion ist verfuegbar.

Version: 1.0.2+3 (internal)
Datei: app-release.apk
SHA256: bbe290bf44c23373801616ec1c9b55169b81dca20e63dd43f73ca792fee43ba4

Bitte vor Installation den Hash pruefen.
Danach Kernflows testen (Login/Gast, Reserve/Activate/Stop, Wallet, Loyalty).
Fehler bitte mit Screenshot, Uhrzeit und Repro-Schritten melden.
```

