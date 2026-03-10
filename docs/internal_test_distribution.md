# Internal Test Distribution (Without Store Release)

Stand: 2026-03-09

Goal: app is release-grade and testable by real users, without public Store release.

## 1) Android test download (recommended now)

This path has no Play Store publication cost and no Store review cycle.

Build signed release APK:

```bash
CUSTOMER_TOP_UP_ENABLED=false \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/build_android_internal_apk.sh
```

Result artifact:

- `/Users/fynn-olegottsch/glanzpunkt_app/build/app/outputs/flutter-apk/app-release.apk`

Suggested tester flow:

1. Upload APK to a private link (for example cloud drive with restricted sharing).
2. Share install guide:
   - Android Settings -> Security -> allow app install from browser/files.
   - Download APK.
   - Open APK and install.
3. Share expected backend env (production-like Supabase) and test accounts.
4. Track tester feedback with app version + APK hash (printed by script).

Dedicated handoff guide (DE):

- `/Users/fynn-olegottsch/glanzpunkt_app/docs/internal_tester_install_guide_de.md`
- `/Users/fynn-olegottsch/glanzpunkt_app/docs/internal_tester_release_handoff_2026-03-10.md`

## 2) iOS testing without App Store release

Important: iOS has stricter distribution rules.

- Free Apple account:
  - local device install from Xcode only (short-lived provisioning, limited practical testing).
- Paid Apple Developer account:
  - TestFlight internal/external testing (recommended for larger iOS tester group).
  - No public App Store release required.

Conclusion: if cost is blocked now, keep iOS tests local via Xcode and run broad external tests first on Android APK.

## 3) Optional browser fallback (no install)

If needed, provide quick access via web build:

```bash
flutter build web --release --dart-define=USE_MOCK_BACKEND=false
```

Then host `build/web` for test users. This is useful for fast feedback, but does not replace mobile-device testing.

## 4) Store-ready policy while not releasing

Keep this quality gate for every candidate build:

```bash
A_EMAIL='...' A_PASSWORD='...' \
B_EMAIL='...' B_PASSWORD='...' \
SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/release_gate.sh
```

Release readiness stays high, even while distribution remains private.
