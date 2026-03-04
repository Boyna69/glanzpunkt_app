# Payment Rollout Decision

Stand: 2026-03-01

## Current State

- `top_up` ist aktuell fuer `authenticated` geoeffnet (Testmodus).
- Customer kann damit derzeit direkt Guthaben aufladen.
- Vor Store-Release braucht es eine finale Entscheidung, ob das so bleibt.

## Decision Options

1. Revert to operator-gated top-up for first store release.
2. Open customer top-up with verified payment provider (Stripe/Adyen/PayPal).
3. Hybrid rollout: customer top-up nur fuer allowlisted test users.

## Recommendation

Empfohlen: Option 1 fuer den naechsten Release-Kandidaten (wenn Payment noch
nicht serverseitig verifiziert ist).

Begruendung:

- kein Risiko durch unvollstaendige Payment-Verifikation
- einfacher Support-Fall in frueher Phase
- klare Trennung zwischen Produktstabilisierung und Monetarisierung

## Exit Criteria to switch to Option 2

- Payment provider integration produktiv und verifiziert
- Server-side payment webhook + idempotency aktiv
- Fraud/abuse handling dokumentiert
- Refund/chargeback Prozess definiert
- E2E tests fuer payment success/fail/retry gruen

## Sign-off

- Entscheider:
- Datum:
- Gewaehlt: `Option 1` / `Option 2` / `Option 3`
