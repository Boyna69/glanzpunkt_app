# Release Readiness Checklist

Stand: 2026-03-04

## 1. Build and Test Gate

- [x] `flutter analyze` is green.
- [x] `flutter test` is green.
- [x] `scripts/release_gate.sh` passes with live Supabase checks.

Reference command:

```bash
A_EMAIL='...' A_PASSWORD='...' \
B_EMAIL='...' B_PASSWORD='...' \
SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/release_gate.sh
```

## 2. Supabase Schema and RPC Gate

- [x] `supabase/rpc_wash_actions.sql` deployed.
- [x] `supabase/operator_action_log.sql` deployed.
- [x] `supabase/operator_kpi_export.sql` deployed.
- [x] `notify pgrst, 'reload schema';` executed after migrations.
- [x] `kpi_export` windows aligned to `Europe/Berlin` (day/week/month, week starts Monday).

Required security state:

- [x] `public.kpi_export(text)` execute granted to `authenticated`.
- [x] no public client write access to protected tables.
- [x] operator-only RPC access enforced via `require_operator_or_owner()`.

## 3. Security Regression Gate

- [x] A/B isolation checks pass.
- [x] RPC contract check passes (deployed names + permission expectations).
- [x] role access check passes (customer denied, operator allowed).
- [x] table exposure check passes (customer cannot read internal/public backup tables).
- [x] operator health check passes (`monitoring_snapshot` + `kpi_export`).
- [x] cleaning workflow e2e passes.
- [x] operator action log e2e passes.
- [x] kpi export e2e passes.

Core scripts:

- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_ab_isolation_login_only.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_rpc_contract_check.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_role_access_check.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_table_exposure_check.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_operator_health_check.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_cleaning_workflow_e2e.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_operator_action_log_e2e.sh`
- `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_operator_kpi_export_e2e.sh`

## 4. Operator Dashboard Runtime Gate

- [x] KPI export shows timezone and explicit window in UI.
- [x] KPI CSV contains local and UTC timestamps.
- [x] KPI error handling hardened (timeout/network readable message).
- [x] last successful KPI preview remains visible during transient failures.
- [x] threshold settings are loaded from backend and shown in dashboard.
- [x] threshold change history is visible in operator dashboard.
- [x] threshold writes are owner-only (operator read-only).
- [x] threshold updates are server-side audit-logged (`update_thresholds`, `source=rpc`).

## 5. Remaining Work Before Store Submission

- [ ] final privacy policy and legal text review (live URLs and contact data).
- [ ] production payment rollout decision (top-up policy for customers vs operator-only).
- [ ] store metadata assets finalization (screenshots, descriptions, age rating).
- [ ] final signing and store upload dry run for Android/iOS release artifacts.

Prepared templates:

- `/Users/fynn-olegottsch/glanzpunkt_app/docs/legal_support_review.md`
- `/Users/fynn-olegottsch/glanzpunkt_app/docs/payment_rollout_decision.md`
- `/Users/fynn-olegottsch/glanzpunkt_app/docs/store_metadata_template.md`

Current blocker notes:

- 2026-03-04: Legal URLs currently fail live HTTP check (final `404` for
  Datenschutz/Impressum), see `docs/legal_support_review.md`.

## 6. Go/No-Go Rule

Release is GO only if all of the following are true:

- [x] latest `release_gate.sh` run is fully green.
- [ ] no critical or high severity bugs open.
- [ ] production Supabase migration set matches repository SQL files.
- [x] operator/customer separation validated on production-like data.

Latest gate evidence:

- 2026-03-01: `release_gate.sh` green (`RUN_SUPABASE_BOX_CYCLE=0`), includes A/B isolation, RPC flow, role access, cleaning workflow, action log, KPI export, owner-threshold e2e.
- 2026-03-01: `release_gate.sh` green (`RUN_SUPABASE_BOX_CYCLE=0`), includes A/B isolation, RPC flow, RPC contract check, role access, cleaning workflow, action log, KPI export, owner-threshold e2e.
- 2026-03-04: `release_smoke.sh` green (`RUN_SUPABASE_BOX_CYCLE=1`), includes A/B isolation, RPC flow/countdown, RPC contract, role access, table exposure, operator health, cleaning workflow, action log, KPI export, owner-threshold e2e, full 1-6 box cycle.
- 2026-03-04: `release_gate.sh` green (`RUN_SUPABASE_BOX_CYCLE=0`) inkl. table exposure + operator health checks.
- 2026-03-04: Android Release-Bundle erfolgreich gebaut: `build/app/outputs/bundle/release/app-release.aab`.
- 2026-03-04: `supabase_migration_parity_report.sh` green (RPC contract, role access, table exposure, operator health).

## 7. CI Gates

- [x] GitHub Actions workflow for release smoke gate exists:
  `/Users/fynn-olegottsch/glanzpunkt_app/.github/workflows/release-gate.yml`
- [x] GitHub Actions workflow for DB drift/parity exists:
  `/Users/fynn-olegottsch/glanzpunkt_app/.github/workflows/supabase-db-parity.yml`
- [x] DB parity hard-fail SQL gate exists:
  `/Users/fynn-olegottsch/glanzpunkt_app/supabase/migration_parity_gate.sql`
- [x] DB parity runner script exists:
  `/Users/fynn-olegottsch/glanzpunkt_app/scripts/supabase_db_parity_gate.sh`
- [x] local git pre-push gate exists (main branch protection fallback):
  `/Users/fynn-olegottsch/glanzpunkt_app/.githooks/pre-push`
  - install via `/Users/fynn-olegottsch/glanzpunkt_app/scripts/install_git_hooks.sh`
  - uses local ignored env file `.release-gate.env` (template: `.release-gate.env.example`)
  - defaults for developer pushes: `RUN_SUPABASE_BOX_CYCLE=0`, `RUN_SUPABASE_QUICK_FLOW_CHECK=0`

Required GitHub Secrets:

- `OPERATOR_EMAIL`
- `OPERATOR_PASSWORD`
- `CUSTOMER_EMAIL`
- `CUSTOMER_PASSWORD`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_DB_URL` (database owner/service-role connection string with SSL)
  - Beispiel:
    `postgresql://postgres:<DB_PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres?sslmode=require`
  - Quelle: Supabase `Project Settings` -> `Database` -> `Connection string` -> `URI`
  - Hinweis: auf Free-Plan kann Direct-DB-Zugriff eingeschraenkt sein; dann bleibt dieser Gate optional und `release-gate.yml` ist der verpflichtende Sicherheits-Gate.
