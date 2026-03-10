# Store Upload Dry-Run Checklist

Stand: 2026-03-10

Ziel: Ein kompletter Testlauf bis kurz vor finalem Veroeffentlichen in Google
Play / Apple App Store.

## 1) Android Dry-Run (Google Play Console)

1. Release-Build erzeugen (Store-Kandidat):
   `CUSTOMER_TOP_UP_ENABLED=false /Users/fynn-olegottsch/glanzpunkt_app/scripts/build_android_release.sh`
2. Pruefen, dass Bundle existiert:
   `build/app/outputs/bundle/release/app-release.aab`
3. Dry-Run-Handover-Bundle vorbereiten (Hashes + Templates):
   `/Users/fynn-olegottsch/glanzpunkt_app/scripts/prepare_store_dry_run_bundle.sh`
4. In Play Console neues Internal-Testing Release anlegen.
5. `app-release.aab` hochladen.
6. Release Notes hinterlegen.
7. Data Safety, Content Rating, App Access, Werbung/Ads checken.
8. Speichern bis Status `Ready to send for review` (ohne echten Go-Live).

## 2) iOS Dry-Run (App Store Connect)

1. `flutter build ipa` (oder Xcode Archive) mit Store-Signing.
2. Upload via Xcode Organizer oder Transporter.
3. In App Store Connect neue Version anlegen.
4. Screenshots, Beschreibung, Keywords, Support/Privacy URL eintragen.
5. Privacy Nutrition Label ausfuellen.
6. Altersfreigabe und Export Compliance beantworten.
7. Speichern bis Status `Prepare for Submission` ohne finalen Submit.

## 3) Abschlusskriterien Dry-Run

- [ ] Android Upload ohne Fehler akzeptiert.
- [ ] iOS Upload ohne Fehler akzeptiert.
- [ ] Keine fehlenden Pflichtfelder in beiden Stores.
- [ ] Store-Texte entsprechen aktuellem Produktumfang.
- [ ] Top-up-Kommunikation passt zu Release-Flag
      (`CUSTOMER_TOP_UP_ENABLED=false`).

## 4) Nachweise (Evidence)

- Screenshot Play Console Release-Status
- Screenshot App Store Connect Version-Status
- Build-Artefakt-Hash oder Dateiname + Timestamp
- Kurzes Release-Protokoll (wer, wann, was hochgeladen)
- Optionaler Evidence-Template-Startpunkt:
  `build/store_dry_run/<BUILD_TAG>/DRY_RUN_EVIDENCE_TEMPLATE.md`
