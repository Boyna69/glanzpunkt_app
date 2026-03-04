# Minimaler Security-Testplan (Pflicht)

Ziel: Verifizieren, dass Tenant-Isolation und Schreibschutz korrekt greifen.

Voraussetzungen:
- SQL ausgefuehrt:
  - `supabase/profile_on_auth_user_insert.sql`
  - `supabase/rls_policies.sql`
  - `supabase/rpc_wash_actions.sql`
- App/Backend laufen gegen dein Supabase-Projekt:
  - `https://ucnvzrpcjkpaltuylvbv.supabase.co`

## 1) User A registrieren -> Boxen sehen -> Session starten

1. In der App mit User A registrieren und einloggen.
2. Home oeffnen: Boxen muessen sichtbar sein (`boxes` select erlaubt).
3. Session starten (ueber RPC):
   - `reserve(box_id)` fuer eine freie Box
   - `activate(box_id, amount)` fuer dieselbe Box mit Betrag
4. Erwartung:
   - Start erfolgreich.
   - In Historie von User A erscheint die Session.

## 2) User B registrieren -> darf Sessions von A NICHT sehen

1. Ausloggen, mit User B registrieren/einloggen.
2. Historie oeffnen (`recent_sessions()` oder `wash_sessions` read-only).
3. Erwartung:
   - Keine Sessions von User A sichtbar.
   - Nur eigene Sessions von User B.

## 3) Direkter Update-Versuch auf boxes muss scheitern

Mit JWT von User A in REST versuchen:

```bash
curl -i -X PATCH "https://ucnvzrpcjkpaltuylvbv.supabase.co/rest/v1/boxes?id=eq.1" \
  -H "apikey: <ANON_OR_PUBLISHABLE_KEY>" \
  -H "Authorization: Bearer <USER_A_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"status":"active"}'
```

Erwartung:
- Request muss fehlschlagen (403/401 oder 0 betroffene Rows je nach Setup).
- Box-Status darf dadurch nicht veraendert werden.

## 4) Direkte Inserts auf wash_sessions/transactions muessen scheitern

Mit JWT von User A in REST versuchen:

```bash
curl -i -X POST "https://ucnvzrpcjkpaltuylvbv.supabase.co/rest/v1/wash_sessions" \
  -H "apikey: <ANON_OR_PUBLISHABLE_KEY>" \
  -H "Authorization: Bearer <USER_A_JWT>" \
  -H "Content-Type: application/json" \
  -d '[{"user_id":"<USER_A_UUID>","box_id":1,"amount":5}]'
```

```bash
curl -i -X POST "https://ucnvzrpcjkpaltuylvbv.supabase.co/rest/v1/transactions" \
  -H "apikey: <ANON_OR_PUBLISHABLE_KEY>" \
  -H "Authorization: Bearer <USER_A_JWT>" \
  -H "Content-Type: application/json" \
  -d '[{"user_id":"<USER_A_UUID>","amount":5}]'
```

Erwartung:
- Beide Requests muessen fehlschlagen (z. B. `42501 permission denied`).
- Session/Transaction-Writes duerfen nur ueber RPCs stattfinden.

## Optionaler Direkt-Check per SQL

Im SQL Editor (Admin-Kontext) zur Sichtpruefung:

```sql
select id, user_id, box_id, amount, started_at, ends_at
from public.wash_sessions
order by started_at desc
limit 20;
```

Zu pruefen:
- Session von User A hat `user_id = A`.
- User B sieht diese Zeile nicht ueber App/API.

## Pass/Fail-Kriterien

- PASS:
  - A kann eigene Session starten und sehen.
  - B sieht A-Sessions nicht.
  - Direktes `boxes`-Update aus App/API scheitert.
  - Direkte Inserts in `wash_sessions`/`transactions` scheitern.
- FAIL:
  - Ein User sieht fremde Sessions.
  - `boxes` laesst sich direkt per Client updaten.
  - `wash_sessions` oder `transactions` lassen direkte Client-Inserts zu.
