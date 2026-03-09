# Internal UAT Runbook

Stand: 2026-03-09

Ziel: Einheitlicher Ablauf fuer interne Tests, damit Fehler reproduzierbar sind
und schnell priorisiert/gefixt werden koennen.

## 1) Scope

- Build: `1.0.2+3 (internal)`
- Artifact:
  `/Users/fynn-olegottsch/glanzpunkt_app/artifacts/internal-test/glanzpunkt_app-1.0.2+3-internal.apk`
- Backend: `USE_MOCK_BACKEND=false`
- Rollen:
  - `Customer` (Normalnutzer)
  - `Operator` (Betreiberansicht)

## 2) Testdurchlauf pro Tester

Jeder Tester meldet am Ende:

- Gesamtstatus: `PASS` oder `FAIL`
- Anzahl gefundener Bugs
- Blocker vorhanden: `ja/nein`

## 3) Pflicht-Testfaelle (Customer)

1. Login mit Account.
2. Gastmodus oeffnen.
3. Boxen laden (Status + Restzeit sichtbar).
4. Reserve -> Activate -> Countdown -> Ende auf `available`.
5. Wallet/Historie laden.
6. Loyalty/Stempel + Reward-Flow pruefen.
7. App Neustart: Zustand bleibt konsistent.

## 4) Pflicht-Testfaelle (Operator)

1. Operator-Login.
2. Monitoring/KPI laden.
3. Cleaning-Plan laden.
4. `mark_box_cleaned` ausfuehren.
5. Role Guard: Customer darf Operator-Funktionen nicht nutzen.

## 5) Bug-Qualitaet (Meldepflicht)

Jeder Bug braucht:

- Geraet + Android-Version
- Uhrzeit
- App-Version (`1.0.2+3`)
- Repro-Schritte (1..n)
- Erwartet vs. tatsaechlich
- Screenshot oder Screenrecord

Vorlage:

- `/Users/fynn-olegottsch/glanzpunkt_app/docs/internal_bug_report_template.md`

## 6) Severity-Regeln

- `Critical`: App startet nicht, Datenverlust, sicherheitsrelevanter Zugriff.
- `High`: Kernflow bricht ab (Reserve/Activate/Stop/Role Guard).
- `Medium`: Feature funktioniert mit Workaround.
- `Low`: UI/Text/kleine Inkonsistenz ohne Funktionsverlust.

## 7) Exit-Kriterien fuer naechsten Candidate

- Keine offenen `Critical`.
- Keine offenen `High` in Kernflows.
- Mindestens 1 erfolgreicher Customer- und 1 erfolgreicher Operator-Durchlauf.
- `release_gate.sh` bleibt gruen.

## 8) Triage-Board

Zur Verwaltung der Rueckmeldungen:

- `/Users/fynn-olegottsch/glanzpunkt_app/docs/internal_uat_triage_board.md`

## 9) In-App UAT Inbox (Operator)

Die Betreiberansicht hat eine eigene `UAT Inbox` fuer strukturiertes Tracking.

Vorgehen:

1. Als `operator/owner` einloggen.
2. In den Einstellungen die `UAT Inbox` oeffnen.
3. Neue Punkte ueber `UAT-Eintrag erfassen` anlegen.
4. Pflichtfelder: `Kurzbeschreibung`, `Bereich`, `Status`, `Severity`.
5. Optional: `Box-ID` und `Target Build` setzen.
6. Fuer die Abarbeitung Filter nutzen:
   - `Nur offene Punkte`
   - Status-Filter (`open`, `in_progress`, `fixed`, `retest`, `closed`)
   - Severity-Filter (`critical`, `high`, `medium`, `low`)
7. Ticket-Aktionen pro Eintrag:
   - `Status setzen`
   - `Owner setzen` (E-Mail, leer = Owner entfernen)

Hinweis:

- Die Inbox liest/schreibt ueber das Operator-Action-Log (RPC, serverseitig
  abgesichert), damit keine lokalen Schattenlisten entstehen.
