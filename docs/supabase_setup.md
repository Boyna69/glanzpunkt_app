# Supabase Setup (Client App)

Die App nutzt Supabase direkt:

- Auth: Email/Password via `POST /auth/v1/token?grant_type=password` und
  `POST /auth/v1/signup`
- Read-Endpoints (PostgREST): `/rest/v1/boxes`, `/rest/v1/wash_sessions`
- Business-Logik (RPC): `/rest/v1/rpc/reserve`, `/activate`, `/stop`,
  `/status`, `/recent_sessions`, `/expire_active_sessions`,
  `/monitoring_snapshot`, `/cancel_reservation`, `/activate_reward`,
  `/top_up`, `/loyalty_status`, `/record_purchase`

Standardmaessig ist die App bereits auf dein Projekt
`https://ucnvzrpcjkpaltuylvbv.supabase.co` konfiguriert. Optional kannst du
weiterhin per `--dart-define` ueberschreiben.

## Empfohlener Start (iOS Simulator)

```bash
flutter run -d "iPhone 16e" \
  --dart-define=USE_MOCK_BACKEND=false \
  --dart-define=SUPABASE_URL=https://ucnvzrpcjkpaltuylvbv.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<DEIN_PUBLISHABLE_KEY> \
  --dart-define=BACKEND_BASE_URL_DEV=https://ucnvzrpcjkpaltuylvbv.supabase.co
```

## Verwendete Header

Default (Client-Key):

- `apikey: <key>`
- `Authorization: Bearer <key>`

Benutzer-Kontext (RLS):

- Wenn ein User-JWT vorhanden ist, setzt die App fuer Requests zusaetzlich
  `Authorization: Bearer <JWT>`.
- Ohne User-JWT funktionieren nur Endpunkte/Policies, die anon/public erlauben.

## Realtime fuer Boxstatus

Die App subscribed live auf `public.boxes` (Supabase Realtime) und nutzt
parallel einen 5s Polling-Fallback. Dadurch bleiben Zustandswechsel robust,
auch wenn Realtime kurzzeitig ausfaellt.

Voraussetzung in Supabase:

```sql
alter publication supabase_realtime add table public.boxes;
```

Optional pruefen:

```sql
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'boxes';
```

## RLS (Soll-Zustand)

Die App erwartet folgende Policies:

- `profiles`: User darf nur eigene Zeile lesen/schreiben (`id = auth.uid()`),
  aber `role` darf vom User nicht selbst geaendert werden.
- `wash_sessions`: User darf nur eigene Zeilen lesen (`user_id = auth.uid()`).
  Inserts/Updates/Deletes nur via RPC (Security Definer).
- `transactions`: User darf nur eigene Zeilen lesen (`user_id = auth.uid()`).
  Inserts/Updates/Deletes nur via RPC (Security Definer).
- `boxes`: `authenticated` `select` erlaubt, keine direkten Client-Writes.

Rollenmodell in `public.profiles.role`:

- `customer` (Default)
- `operator`
- `owner`

`wash_sessions.user_id` referenziert `auth.users.id` (UUID).

Fertiges SQL zum Anwenden:

- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/rls_policies.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/profile_on_auth_user_insert.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/operator_role_admin.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/rpc_wash_actions.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/boxes_hardened_policies.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/performance_indexes.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/monitoring_queries.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/cleanup_legacy_data.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/harden_internal_public_tables_rls.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/operator_action_log.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/operator_threshold_settings.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/operator_kpi_export.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/scheduler_expire_active_sessions.sql`
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/customer_topup_enable.sql` (optional, Testmodus fuer Customer-Top-up)
- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/migration_parity_validation.sql` (read-only Validierungsabfragen)

Im Supabase SQL Editor ausfuehren, damit bestehende Policies ersetzt und auf
den obigen Sollzustand gesetzt werden.

Empfohlene Reihenfolge:

1. `profile_on_auth_user_insert.sql` (Auto-Profil bei Registrierung + Backfill)
2. `operator_role_admin.sql` (rollenmodell customer/operator/owner sicherstellen)
3. `rls_policies.sql` (Isolation/Policy-Hardening)
4. `rpc_wash_actions.sql` (Action-Schicht fuer Waschlogik)
5. `boxes_hardened_policies.sql` (optional: boxes nur fuer authenticated lesbar)
6. `performance_indexes.sql` (einmalig, Performance)
7. `cleanup_legacy_data.sql` (einmalig, Altlasten bereinigen)
8. `scheduler_expire_active_sessions.sql` (empfohlen: Auto-Reconciliation jede Minute)
9. `harden_internal_public_tables_rls.sql` (RLS/REVOKE fuer interne Legacy-/Runtime-Tabellen)
10. `operator_action_log.sql` (Operator-Audit-Log + Filter-RPC + append-only guard)
11. `operator_threshold_settings.sql` (konfigurierbare Betreiber-Thresholds)
12. `operator_kpi_export.sql` (KPI-Export Tag/Woche/Monat fuer Betreiber)
13. optional: `customer_topup_enable.sql` (Customer-Top-up fuer Tests freigeben)

## Betreiberzugriff (harte Trennung)

`monitoring_snapshot` und `expire_active_sessions` sind serverseitig auf
`operator/owner` begrenzt. Ein normaler `customer` bekommt `forbidden`.

Wichtig: Betreiberrolle wird **nicht** im Client gesetzt, sondern nur im SQL
Editor (Admin/Owner-Kontext), z. B.:

```sql
update public.profiles
set role = 'operator'
where id = '<SUPABASE_USER_UUID>';
```

Oder fuer Inhaber:

```sql
update public.profiles
set role = 'owner'
where id = '<SUPABASE_USER_UUID>';
```

Hinweis: Falls `public.profiles` weitere `NOT NULL` Spalten ohne Default hat,
muessen diese im Trigger-`insert` ebenfalls gesetzt oder mit Default versehen
werden.

## Action Layer (RPC)

Folgende Funktionen stehen danach fuer die App bereit:

- `public.reserve(box_id integer)`
- `public.activate(box_id integer, amount integer)`
- `public.stop(session_id text)`
- `public.status(box_id integer)`
- `public.recent_sessions(max_rows integer default 30)`
- `public.expire_active_sessions()`
- `public.monitoring_snapshot()`
- `public.top_up(amount integer)` (aktuell offen fuer `authenticated`, Testmodus)
- `public.expire_active_sessions_internal()` (nur fuer Scheduler, kein Client-RPC)

Self-Service Konto-Loeschung laeuft aus Sicherheitsgruenden **nicht** als
SQL-RPC, sondern als Edge Function mit `service_role`.

## Konto-Loeschung (Edge Function)

Datei im Repo:

- `/Users/fynn-olegottsch/glanzpunkt_app/supabase/functions/delete-account/index.ts`

Deploy:

```bash
supabase functions deploy delete-account \
  --project-ref ucnvzrpcjkpaltuylvbv
```

Die App ruft danach auf:

- `POST /functions/v1/delete-account` (mit User-JWT)

Die Function validiert den eingeloggten User und loescht den Auth-User via
`auth.admin.deleteUser(...)` mit `service_role`.

Die Wasch-Aktionen ruft die App direkt per RPC auf; Tabellenzugriffe bleiben
durch RLS/Grants abgesichert. Die Konto-Loeschung laeuft separat ueber die
Edge Function.

Hinweis zu `top_up`:
- Derzeit ist `top_up` fuer `authenticated` geoeffnet, damit Kundenfluss
  End-to-End getestet werden kann.
- Vor Production-Release sollte diese Oeffnung erneut bewertet und
  ggf. wieder auf Betreiber-/payment-verifizierten Flow gehaertet werden.

Hinweis zu `expiredSessions`:
- Rueckgabe von `expire_active_sessions`: `expiredSessions` entspricht nun
  **neu abgelaufenen Sessions seit letztem Reconcile-Lauf** (nicht mehr
  historischer Gesamtwert).
- Zusatzfeld: `expiredSessionsTotalHistorical` fuer Gesamtkontext.

Hinweis zur `boxes_hardened_policies.sql`:
- `boxes` ist dann nur fuer `authenticated` lesbar.
- Gast-Nutzer (`anon`) koennen keine Boxliste mehr lesen.

## Scheduler (empfohlen)

Damit Boxen bei Session-/Reservierungsablauf automatisch sauber zurueckgesetzt
werden, richte den Cron-Job ein:

- SQL: `/Users/fynn-olegottsch/glanzpunkt_app/supabase/scheduler_expire_active_sessions.sql`
- Intervall: jede Minute (`* * * * *`)
- Intern genutzt: `public.expire_active_sessions_internal()`

Pruefen:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'glanzpunkt_expire_active_sessions';
```

## Hinweis zur Sicherheit

- Keys nicht fest in Code committen.
- Fuer produktive Nutzung regelmaessig rotieren.
- Service-Role-Keys gehoeren niemals in die mobile App.

## Monitoring

- SQL-Checks fuer Betrieb/Monitoring: `supabase/monitoring_queries.sql`
- Empfohlen: taeglich stale reservations und sessions mit `box_id is null`
  pruefen.
- Schneller Box-Flow-Check (1-6): `scripts/supabase_box_cycle_e2e.sh`
  mit Key (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `A_EMAIL`, `A_PASSWORD`.
- Rollen-Zugriffscheck (customer vs operator):
  `scripts/supabase_role_access_check.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`, `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
- Table-Exposure-Check (customer darf interne Tabellen nicht lesen):
  `scripts/supabase_table_exposure_check.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`.
- Operator-Health-Check (Monitoring-Snapshot + KPI-Export):
  `scripts/supabase_operator_health_check.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
- Migration-Paritaetsreport (API/RPC/RLS-Verhalten in einem Lauf):
  `scripts/supabase_migration_parity_report.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`, `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`.
- SQL-Paritaets-Validierung (Owner-Kontext im SQL Editor):
  `supabase/migration_parity_validation.sql`
- RPC-Contract-Check (deployed RPC-Namen + Berechtigungen):
  `scripts/supabase_rpc_contract_check.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`, `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
  Der Check ist in `scripts/release_smoke.sh` standardmaessig aktiv
  (`RUN_SUPABASE_CONTRACT_CHECK=1`).
- Operator-Action-Log E2E:
  `scripts/supabase_operator_action_log_e2e.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`, `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
  Hinweis: benoetigt die aktuelle SQL-Migration `supabase/operator_action_log.sql`
  inklusive RPC `public.list_operator_actions_filtered(...)`.
- KPI-Export E2E:
  `scripts/supabase_operator_kpi_export_e2e.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`, `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
  Hinweis: benoetigt die SQL-Migration `supabase/operator_kpi_export.sql`
  inklusive RPC `public.kpi_export(period text)`.
- Operator-Threshold-Settings E2E:
  `scripts/supabase_operator_threshold_settings_e2e.sh` mit Key
  (`SUPABASE_PUBLISHABLE_KEY` oder legacy `SUPABASE_ANON_KEY`),
  `CUSTOMER_EMAIL`, `CUSTOMER_PASSWORD`, `OPERATOR_EMAIL`, `OPERATOR_PASSWORD`.
  Hinweis: benoetigt die SQL-Migration `supabase/operator_threshold_settings.sql`
  inklusive RPC `public.get_operator_threshold_settings()` und
  `public.set_operator_threshold_settings(integer, integer)`.
  Schreiben ist auf Rolle `owner` begrenzt; optionaler Negativtest fuer
  Nicht-Owner per `NON_OWNER_EMAIL`/`NON_OWNER_PASSWORD`.
  Der Set-RPC schreibt serverseitig einen Audit-Eintrag `update_thresholds`
  (source `rpc`) in `operator_action_log` falls `log_operator_action(...)` vorhanden ist.
- KPI-Export (Tag/Woche/Monat) im Betreiber-Dashboard:
  benoetigt SQL-Migration `supabase/operator_kpi_export.sql`
  inklusive RPC `public.kpi_export(period text)` (mit Vorzeitraum-/Delta-Feldern).
  Fachlicher TZ-Check (im Supabase SQL-Editor):

```sql
with now_ref as (
  select now() as now_utc
),
expected as (
  select
    (date_trunc('day', timezone('Europe/Berlin', now_utc)) at time zone 'Europe/Berlin') as day_start,
    (date_trunc('week', timezone('Europe/Berlin', now_utc)) at time zone 'Europe/Berlin') as week_start,
    (date_trunc('month', timezone('Europe/Berlin', now_utc)) at time zone 'Europe/Berlin') as month_start
  from now_ref
),
kpi as (
  select
    public.kpi_export('day') as day_payload,
    public.kpi_export('week') as week_payload,
    public.kpi_export('month') as month_payload
)
select
  (day_payload->>'window_start')::timestamptz as rpc_day_start,
  expected.day_start as expected_day_start,
  ((day_payload->>'window_start')::timestamptz = expected.day_start) as day_ok,
  (week_payload->>'window_start')::timestamptz as rpc_week_start,
  expected.week_start as expected_week_start,
  ((week_payload->>'window_start')::timestamptz = expected.week_start) as week_ok,
  (month_payload->>'window_start')::timestamptz as rpc_month_start,
  expected.month_start as expected_month_start,
  ((month_payload->>'window_start')::timestamptz = expected.month_start) as month_ok
from kpi
cross join expected;
```
- Quick-Fix in der App nutzt `public.expire_active_sessions()` und setzt
  stale reservations/haengende reserved boxes automatisch zurueck.
