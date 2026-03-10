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
- Store screenshot capture guide (DE):
  `docs/store_screenshot_capture_guide_de.md`
- Internal test distribution (without Store release):
  `docs/internal_test_distribution.md`
- Internal tester install guide (DE):
  `docs/internal_tester_install_guide_de.md`
- Internal tester release handoff (2026-03-10):
  `docs/internal_tester_release_handoff_2026-03-10.md`
- Internal APK distribution runbook (DE):
  `docs/internal_apk_distribution_runbook_de.md`
- Internal UAT runbook + bug triage templates:
  `docs/internal_uat_runbook.md`
- Security rotation runbook (DE):
  `docs/security_rotation_runbook_de.md`
- Store metadata handover (DE):
  `docs/store_metadata_handover_de.md`
- PR review + merge quicksteps (DE):
  `docs/pr_review_merge_quicksteps_de.md`
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
- UAT Inbox (operator-only) liest Betreiberaktionen als Ticket-Feed und unterstuetzt:
  - Suche + Status/Severity-Filter + `Nur offene Punkte`
  - manuellen UAT-Eintrag mit standardisiertem Payload (`uat_status`, `severity`, `target_build`)
  - Status-Update + Owner-Zuweisung direkt pro Ticket (RPC-basiert, auditierbar)
  - dedizierte Widget-Tests in `test/uat_inbox_screen_test.dart`
  - dafuer muss in Supabase zusaetzlich `supabase/operator_uat_ticket_actions.sql` ausgefuehrt sein
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
  - optional candidate boxes for quick-flow (first available is used):
    `SUPABASE_QUICK_FLOW_BOX_IDS='1 2 3 4 5 6'`
  - optional full 1-6 box cycle:
    `RUN_SUPABASE_BOX_CYCLE=1`
  - optional UAT backlog hard gate (fails on open critical/high):
    `RUN_SUPABASE_UAT_BACKLOG_GATE=1`
    - scan window size (1..200): `UAT_GATE_MAX_ROWS=200`
  - optional legal/support live check:
    `RUN_LEGAL_SUPPORT_CHECK=1`
- One-command release gate (analyze + tests + Supabase security + cleaning + operator KPI export + box cycle):
  `scripts/release_gate.sh`
  - example:
    `A_EMAIL=... A_PASSWORD=... B_EMAIL=... B_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/release_gate.sh`
    (alternativ legacy: `SUPABASE_ANON_KEY=...`)
  - optional lighter run without full box cycle:
    `RUN_SUPABASE_BOX_CYCLE=0 ... scripts/release_gate.sh`
- Quick release gate profile (default for local pre-push):
  `scripts/release_gate_quick.sh`
  - runs without quick-flow and without full 1-6 box cycle
  - local default: UAT backlog gate aus (`RUN_SUPABASE_UAT_BACKLOG_GATE=0`)
- Full release gate profile (deepest runtime check):
  `scripts/release_gate_full.sh`
  - forces quick-flow and full 1-6 box cycle
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
    - erzwingt `RUN_SUPABASE_UAT_BACKLOG_GATE=1` (kein offenes critical/high UAT im CI)
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
  - behavior: pushing to `main` runs `scripts/release_gate_quick.sh` and blocks push on failure
  - pre-push runs secret hygiene check (`scripts/security_secrets_check.sh`)
  - pre-push always includes UAT ticket status/owner E2E (`scripts/supabase_uat_ticket_update_e2e.sh`)
  - pre-push enforces UAT backlog hard gate (`RUN_SUPABASE_UAT_BACKLOG_GATE=1`)
  - emergency bypass: `SKIP_RELEASE_GATE=1 git push` (not recommended)
- RPC contract check (verifies deployed RPC names/permissions, no dangerous writes):
  `scripts/supabase_rpc_contract_check.sh`
  - requires key (`SUPABASE_ANON_KEY` oder `SUPABASE_PUBLISHABLE_KEY`) and both account credentials
- Operator action log E2E (operator write/read, customer deny):
  `scripts/supabase_operator_action_log_e2e.sh`
- UAT ticket status/owner E2E (operator allowed, customer deny):
  `scripts/supabase_uat_ticket_update_e2e.sh`
- UAT backlog gate (no open critical/high UAT tickets in latest window):
  `scripts/supabase_uat_backlog_gate.sh`
- UAT E2E cleanup helper (stale test tickets, default dry-run):
  `scripts/supabase_uat_cleanup_e2e_tickets.sh`
  - apply mode:
    `APPLY=1 OPERATOR_EMAIL=... OPERATOR_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/supabase_uat_cleanup_e2e_tickets.sh`
- KPI export E2E (operator allowed for day/week/month, customer deny):
  `scripts/supabase_operator_kpi_export_e2e.sh`
- Operator threshold settings E2E (owner get/set allowed, customer deny):
  `scripts/supabase_operator_threshold_settings_e2e.sh`
- Secret hygiene check (blocks committed keys/tokens and non-placeholder env template values):
  `scripts/security_secrets_check.sh`
- Internal release bundle packager (APK + checksum + notes):
  `scripts/package_internal_release_bundle.sh`
- Store dry-run bundle packager (AAB/APK + hashes + evidence template):
  `scripts/prepare_store_dry_run_bundle.sh`
- Store screenshot pack helpers:
  `scripts/init_store_screenshot_pack.sh`
  `scripts/validate_store_screenshot_pack.sh`
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
- Android internal test APK build helper (direct install for testers):
  - `scripts/build_android_internal_apk.sh`
  - example:
    `CUSTOMER_TOP_UP_ENABLED=false scripts/build_android_internal_apk.sh`
