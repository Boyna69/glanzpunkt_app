# PR Review + Merge Quicksteps (DE)

Stand: 2026-03-10

Ziel: PR #1 mergen trotz Policy `require_last_push_approval`.

## Voraussetzungen

- Zweiter GitHub-Account mit Schreibzugriff auf das Repo
  `Boyna69/glanzpunkt_app`.

## Schritte

1. Mit zweitem Account bei GitHub anmelden.
2. PR oeffnen: `https://github.com/Boyna69/glanzpunkt_app/pull/1`
3. Warten bis Checks gruen sind (`Flutter + Supabase Release Gate`).
4. `Files changed` kurz pruefen.
5. `Review changes` -> `Approve` -> `Submit review`.
6. Zurueck auf Hauptaccount.
7. PR mergen (Squash + Delete branch).

## Danach lokal synchronisieren

```bash
cd /Users/fynn-olegottsch/glanzpunkt_app
git checkout main
git pull origin main
```

