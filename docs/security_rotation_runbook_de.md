# Security Rotation Runbook (Supabase + GitHub)

Stand: 2026-03-10

Ziel: Nach Public-Repo-Exposure alte Test-Zugaenge und Keys ersetzen und sicher
weiterarbeiten.

## Schritt 1: Supabase Publishable Key rotieren

1. Supabase Dashboard -> Project Settings -> API.
2. Neuen Publishable Key erzeugen (oder vorhandenen Key rotieren).
3. Alten Key noch nicht sofort loeschen (kurze Uebergangsphase).

## Schritt 2: Test-Account-Passwoerter rotieren

1. Supabase Dashboard -> Authentication -> Users.
2. Testnutzer `operator` und `customer` oeffnen.
3. Passwoerter auf neue starke Werte setzen (mind. 20 Zeichen).
4. Alte `Test1`-Passwoerter nicht mehr verwenden.

## Schritt 3: GitHub Secrets aktualisieren

Repository: `Boyna69/glanzpunkt_app`  
Pfad: Settings -> Secrets and variables -> Actions -> Repository secrets

Aktualisieren:

- `SUPABASE_PUBLISHABLE_KEY`
- `OPERATOR_EMAIL`
- `OPERATOR_PASSWORD`
- `CUSTOMER_EMAIL`
- `CUSTOMER_PASSWORD`

## Schritt 4: Lokale Gate-Env aktualisieren

Datei: `/Users/fynn-olegottsch/glanzpunkt_app/.release-gate.env`  
Falls nicht vorhanden: aus `.release-gate.env.example` kopieren.

Werte aktualisieren:

- `A_EMAIL`, `A_PASSWORD`
- `B_EMAIL`, `B_PASSWORD`
- `SUPABASE_PUBLISHABLE_KEY`

## Schritt 5: Rotation verifizieren

Im Projektordner:

```bash
bash scripts/security_secrets_check.sh

A_EMAIL='...' A_PASSWORD='...' \
B_EMAIL='...' B_PASSWORD='...' \
SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/release_gate_quick.sh
```

Erwartung:

- `SECRET HYGIENE CHECK PASSED`
- `SMOKE CHECKS PASSED`

Optionaler Legacy-Guard (sollte nach Rotation PASS liefern):

```bash
LEGACY_SUPABASE_KEY='sb_publishable_...' \
LEGACY_OPERATOR_EMAIL='old-operator@example.com' LEGACY_OPERATOR_PASSWORD='old-password' \
LEGACY_CUSTOMER_EMAIL='old-customer@example.com' LEGACY_CUSTOMER_PASSWORD='old-password' \
/Users/fynn-olegottsch/glanzpunkt_app/scripts/rotation_guard_legacy_credentials.sh
```

Erwartung:

- `ROTATION GUARD PASSED`
- Alte Keys/Passwoerter funktionieren nicht mehr.

## Schritt 6: Alte Werte deaktivieren

Nach erfolgreicher Verifikation:

1. Alten Publishable Key in Supabase widerrufen/entfernen.
2. Alte Test-Passwoerter final invalidieren.

## Hinweise

- Keys und Passwoerter nie im Repository speichern.
- Nur in GitHub Secrets und lokale, ignorierte Env-Dateien schreiben.
