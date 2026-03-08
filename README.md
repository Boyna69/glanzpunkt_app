# glanzpunkt_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Project Notes

- Minimaler Security-Testplan (A/B-Isolation + boxes write block):
  `docs/minimal_security_testplan.md`
- Backend contract draft for wash flow:
  `docs/backend_api_contract.md`
- Release readiness and go/no-go checklist:
  `docs/release_readiness_checklist.md`
- Legal/support pre-store review checklist:
  `docs/legal_support_review.md`
- Payment rollout decision template:
  `docs/payment_rollout_decision.md`
- Store metadata template:
  `docs/store_metadata_template.md`
- Store metadata draft (ready-to-fill, DE):
  `docs/store_metadata_release_draft_de.md`
- Store upload dry-run checklist:
  `docs/store_upload_dry_run_checklist.md`
- Backend mode switch via Dart define:
  - Mock (default): `flutter run`
  - Remote API: `flutter run --dart-define=USE_MOCK_BACKEND=false --dart-define=BACKEND_BASE_URL_DEV=https://ucnvzrpcjkpaltuylvbv.supabase.co`
- Supabase API key selection in app:
  - Preferred: `SUPABASE_PUBLISHABLE_KEY`
  - Fallback (legacy): `SUPABASE_ANON_KEY`
- QR payload format (current parser):
  - `glanzpunkt://box?box=3&sig=abc123`
  - Fallback: plain box number like `3`
  - `sig` is forwarded as `boxSignature` to backend reserve request
  - Camera scan is integrated in start flow (mobile)
- Start flow shows payment state transitions in UI:
  - `Idle -> Pending -> Success/Failed`
- Active box sessions are synced from backend status endpoint every 15 seconds.
- Home screen shows backend sync health and supports manual sync via app bar.
- Box cards open a detail page with per-box sync/session information.
- Home screen includes live KPI chips (free/active/cleaning/occupancy).
- Home and start flow include dismissible persistent error panels.
- Box detail screen includes a per-box session timeline with timestamps.
- Box detail supports manual stop/abort for active sessions.
- Login supports continuing without account via "Als Gast fortfahren".
- Settings include a self-service account deletion action ("Konto loeschen").
  - Backend endpoint: `POST /functions/v1/delete-account` (Supabase Edge Function)
- Home shows the latest global timeline events across boxes.
- Guest mode shows account-upgrade CTAs in home and wash-start screens.
- Register screen upgrades an active guest session into a full account.
- Loyalty is gated to account users (guest users see upgrade prompts).
- Auth session (guest/account) is persisted and restored on app start.
- Last wash-start selection (box/amount/identification) is persisted locally.
- Box timeline/recent events are persisted and restored after app restart.
- Timeline retention keeps only the last 7 days of box events.
- Box detail screen can clear timeline events for the selected box.
- Manual box selection requires an explicit in-place confirmation before start.
- Session end now uses a realistic transition: `active -> cleaning -> available`.
- Home and box-detail UI show clearer countdown semantics for cleaning vs active.
- Start flow now shows explicit per-box availability/block reasons (including cleaning countdown).
- Start button in flow is now state-driven (selection, availability, and manual confirmation).
- Home synchronizes box states via Supabase Realtime (with 5s polling fallback).
- Home shows the active sync channel (Realtime live vs Polling fallback).
- Home-Appbar hat ein Overflow mit manuellem "Quick-Fix jetzt" (expire/release).
- Quick-Fix-Aktionen sind mit einem Bestaetigungsdialog abgesichert.
- Betreiberzugriff ist rollenbasiert (`profiles.role`: customer/operator/owner).
- Monitoring und Quick-Fix sind serverseitig auf operator/owner beschraenkt.
- Native launch screens (Android/iOS) use the app blue background instead of white.
- Launcher icons can be regenerated without alpha (iOS store-safe) via:
  `scripts/regenerate_app_icons.sh`
- Android release signing reads `android/key.properties` (template:
  `android/key.properties.example`).
- Splash and login include branding with logo and a short claim.
- Loyalty stamps are now collected automatically after successful wash starts.
- Loyalty screen is read-only for users (no manual add/reset controls).
- Loyalty UI now has 10 fixed stamp slots and animated progress feedback.
- Loyalty reward state now highlights with a dedicated premium reward card at 10/10.
- Reward can be redeemed in start flow as a dedicated 10-minute wash slot after box selection.
- Reward redemption now requires an explicit confirmation dialog before start.
- Loyalty shows a small history of consumed rewards (box + timestamp).
- Wallet & Buchungen Screen zeigt Guthaben, Aufladungen, Buchungen und abgeschlossene Sessions.
- Fehler-UX wurde vereinheitlicht (gemeinsame Error-Banner-Komponente in zentralen Screens).
- Settings now include a dedicated Monitoring screen with live backend KPIs.
- Monitoring includes an ops health traffic light and a Quick-Fix action for stale reservations.
- Betreiber-Dashboard zeigt Betriebswarnungen fuer Reinigung faellig, stale Reservierungen und lange aktive Boxen (mit Quick-Aktionen).
- Betreiber-Dashboard zeigt ein serverseitiges Operator-Aktionsprotokoll (Supabase RPC, geraeteuebergreifend) fuer Quick-Fix, Status-Refresh und Reinigungsaktionen inkl. Erfolg/Fehler.
- Operator-Aktionsprotokoll ist filterbar (Status/Box/Suche) und als CSV-Datei lokal speicherbar oder per Share-Sheet exportierbar.
  - dafuer muss in Supabase die aktuelle Version von `supabase/operator_action_log.sql` ausgefuehrt sein (`list_operator_actions_filtered` RPC).
  - Audit-Haertung: `operator_action_log` ist als append-only konzipiert (keine App-Updates/Deletes; Trigger blockt DB-Updates/Deletes).
- Betreiber-Thresholds (Reinigungsintervall + Long-Active-Warnung) werden serverseitig aus Supabase geladen.
  - dafuer muss in Supabase `supabase/operator_threshold_settings.sql` ausgefuehrt sein (`get_operator_threshold_settings` / `set_operator_threshold_settings` RPCs).
  - Schreiben ist auf `owner` begrenzt (operator kann lesen, aber nicht aendern).
  - Threshold-Aenderungen werden serverseitig als Operator-Aktion `update_thresholds` (source `rpc`) audit-logged.
- KPI-Export v2 im Betreiberbereich: CSV fuer Tag/Woche/Monat (lokal speichern oder teilen).
  - dafuer muss in Supabase `supabase/operator_kpi_export.sql` ausgefuehrt sein (`public.kpi_export(period)` RPC).
  - CSV enthaelt jetzt sowohl lokale Zeitstempel (Europe/Berlin) als auch UTC-Felder (`*_utc`) fuer klare Auswertung.
  - KPI zeigt Delta zum Vorzeitraum (Sessions/Umsatz/Top-up inkl. Prozent, falls Vergleichsdaten vorhanden).
  - Bei Timeout/Netzwerkfehlern zeigt das Dashboard eine klare Fehlermeldung und behaelt die letzte erfolgreiche KPI-Vorschau als Fallback.
  - Ein KPI-Kurzbericht kann direkt aus dem Dashboard geteilt oder in die Zwischenablage kopiert werden.
- Production smoke checks script:
  `scripts/release_smoke.sh`
  - local only: `scripts/release_smoke.sh`
  - with Supabase live checks:
    `RUN_SUPABASE_SMOKE=1 A_EMAIL=... A_PASSWORD=... B_EMAIL=... B_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/release_smoke.sh`
    (alternativ legacy: `SUPABASE_ANON_KEY=...`)
  - optional disable RPC contract check (default enabled):
    `RUN_SUPABASE_CONTRACT_CHECK=0`
  - optional disable table exposure check (default enabled):
    `RUN_SUPABASE_TABLE_EXPOSURE_CHECK=0`
  - optional disable operator health check (default enabled):
    `RUN_SUPABASE_OPERATOR_HEALTH_CHECK=0`
  - optional fuer owner-only Threshold-Checks:
    `OWNER_EMAIL=... OWNER_PASSWORD=...`
  - optional runtime for expiry smoke (default `130` seconds):
    `SUPABASE_WAIT_SECONDS=130`
  - optional full 1-6 box cycle:
    `RUN_SUPABASE_BOX_CYCLE=1`
  - optional legal/support live check:
    `RUN_LEGAL_SUPPORT_CHECK=1`
- One-command release gate (analyze + tests + Supabase security + cleaning + operator KPI export + box cycle):
  `scripts/release_gate.sh`
  - example:
    `A_EMAIL=... A_PASSWORD=... B_EMAIL=... B_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/release_gate.sh`
    (alternativ legacy: `SUPABASE_ANON_KEY=...`)
  - optional lighter run without full box cycle:
    `RUN_SUPABASE_BOX_CYCLE=0 ... scripts/release_gate.sh`
- Full box cycle E2E script (reserve -> activate -> stop -> status for box 1-6):
  `scripts/supabase_box_cycle_e2e.sh`
  - example:
    `A_EMAIL=... A_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/supabase_box_cycle_e2e.sh`
    (alternativ legacy: `SUPABASE_ANON_KEY=...`)
- Role access check (customer denied, operator allowed for monitoring/quick-fix):
  `scripts/supabase_role_access_check.sh`
  - requires key (`SUPABASE_ANON_KEY` oder `SUPABASE_PUBLISHABLE_KEY`) and both account credentials
- Table exposure check (customer must not read internal/public backup tables):
  `scripts/supabase_table_exposure_check.sh`
  - requires key (`SUPABASE_ANON_KEY` oder `SUPABASE_PUBLISHABLE_KEY`) and customer credentials
- Operator health check (monitoring snapshot + KPI export reachable):
  `scripts/supabase_operator_health_check.sh`
  - requires key (`SUPABASE_ANON_KEY` oder `SUPABASE_PUBLISHABLE_KEY`) and operator credentials
- Migration parity report (RPC/RLS/table exposure/operator health in one run):
  `scripts/supabase_migration_parity_report.sh`
  - requires key and both operator/customer credentials
- DB parity hard gate (owner connection, fails on schema/grant/trigger drift):
  `scripts/supabase_db_parity_gate.sh`
  - requires: `SUPABASE_DB_URL`
  - Supabase source: `Project Settings -> Database -> Connection string -> URI`
  - if `SUPABASE_DB_URL` is not available (e.g. free plan), the CI DB parity workflow is skipped and API-level `release_gate.sh` remains the required gate
- CI workflows:
  - `/Users/fynn-olegottsch/glanzpunkt_app/.github/workflows/release-gate.yml`
  - `/Users/fynn-olegottsch/glanzpunkt_app/.github/workflows/supabase-db-parity.yml`
  - required repository secrets:
    `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`, `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`,
    `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_DB_URL`
  - optional repository variables for legal/support live check:
    `LEGAL_PRIVACY_URL`, `LEGAL_IMPRINT_URL`, `SUPPORT_EMAIL`
- Local push protection for `main` (free-plan replacement for branch protection):
  - install once: `scripts/install_git_hooks.sh`
  - credentials file template: `.release-gate.env.example`
  - create local file (ignored by git): `.release-gate.env`
  - behavior: pushing to `main` runs `scripts/release_gate.sh` and blocks push on failure
  - pre-push defaults: `RUN_SUPABASE_BOX_CYCLE=0` and `RUN_SUPABASE_QUICK_FLOW_CHECK=0` (faster/less flaky)
  - emergency bypass: `SKIP_RELEASE_GATE=1 git push` (not recommended)
- RPC contract check (verifies deployed RPC names/permissions, no dangerous writes):
  `scripts/supabase_rpc_contract_check.sh`
  - requires key (`SUPABASE_ANON_KEY` oder `SUPABASE_PUBLISHABLE_KEY`) and both account credentials
- Operator action log E2E (operator write/read, customer deny):
  `scripts/supabase_operator_action_log_e2e.sh`
- KPI export E2E (operator allowed for day/week/month, customer deny):
  `scripts/supabase_operator_kpi_export_e2e.sh`
- Operator threshold settings E2E (owner get/set allowed, customer deny):
  `scripts/supabase_operator_threshold_settings_e2e.sh`
- Supabase operational SQL helpers:
  - `supabase/performance_indexes.sql`
  - `supabase/monitoring_queries.sql`
  - `supabase/cleanup_legacy_data.sql`
  - `supabase/operator_role_admin.sql`
  - `supabase/operator_action_log.sql`
  - `supabase/operator_threshold_settings.sql`
  - `supabase/operator_kpi_export.sql`
  - `supabase/scheduler_expire_active_sessions.sql`
  - `supabase/harden_internal_public_tables_rls.sql`
  - `supabase/harden_wash_sessions_legacy_backup.sql`
- Android release build helper (forces `USE_MOCK_BACKEND=false`):
  - `scripts/build_android_release.sh`
  - optional customer top-up toggle for release builds:
    `CUSTOMER_TOP_UP_ENABLED=false scripts/build_android_release.sh`
