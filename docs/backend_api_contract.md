# Wash Backend API Contract (v1)

This document defines the backend contract that the app already models in
`WashBackendGateway`.

## Action-first backend mode (Supabase RPC)

The backend can expose action endpoints backed by RPC/stored procedures:

- `reserve(box_id)`
- `activate(box_id, amount)`
- `stop(session_id)`
- `status(box_id)`
- `recent_sessions()`
- `cancel_reservation(box_id)`
- `activate_reward(box_id)`

Edge Functions can act as thin wrappers that validate payload and call these
RPC actions.

## Access control

- `customer`: wash flow + own sessions/transactions/profile.
- `operator` / `owner`: zusaetzlich Monitoring- und Operations-RPCs
  (z. B. `monitoring_snapshot`, `expire_active_sessions`).
- `top_up(amount)`: aktuell fuer alle authenticated User offen
  (Testmodus fuer End-to-End-Validierung).
- Role source: `public.profiles.role` (server-authoritative).

## 1) Reserve Box (Edge Function)

- Method: `POST`
- Path: `/functions/v1/reserve`
- Purpose: lock a free box for a short period before payment activation.

Request body:

```json
{
  "boxNumber": 3,
  "amountEuro": 10,
  "identificationMethod": "qr",
  "boxSignature": "abc123"
}
```

`boxSignature` is optional and used when identification method is `qr`.

Response body:

```json
{
  "reservationToken": "res_3_123456",
  "reservedUntil": "2026-02-19T20:45:00Z"
}
```

Error response example:

```json
{
  "code": "invalid_signature",
  "message": "QR signature is invalid"
}
```

## 2) Activate Reserved Box (Edge Function)

- Method: `POST`
- Path: `/functions/v1/activate`
- Purpose: start the wash session after successful payment.

Request body:

```json
{
  "reservationToken": "res_3_123456"
}
```

Response body:

```json
{
  "sessionId": "wash_987654",
  "runtimeMinutes": 20
}
```

## 3) Stop Active Session (Edge Function)

- Method: `POST`
- Path: `/functions/v1/stop`
- Purpose: abort the currently active session for a box.

Request body:

```json
{
  "boxNumber": 3
}
```

Error response example:

```json
{
  "code": "session_not_active",
  "message": "No active session for this box"
}
```

## 4) Get Box Status (Edge Function)

- Method: `POST`
- Path: `/functions/v1/status`
- Purpose: read authoritative state from backend/controller.

Response body:

```json
{
  "boxNumber": 3
}
```

Response body:

```json
{
  "boxNumber": 3,
  "state": "active",
  "remainingMinutes": 16
}
```

## 5) Get Recent Wash Sessions (PostgREST read)

- Method: `GET`
- Path: `/rest/v1/wash_sessions?user_id=eq.{userId}`
- Purpose: read recent session history for app history/admin surfaces.

Response body:

```json
[
  {
    "id": 987654,
    "box_id": 3,
    "user_id": "uuid",
    "started_at": "2026-02-20T12:00:00Z",
    "ends_at": "2026-02-20T12:20:00Z",
    "amount": 10
  }
]
```

## State values

- `available`
- `reserved`
- `active`
- `cleaning`
- `out_of_service`
- `occupied` (legacy alias, app maps to `active`)

## Realtime contract

Zusatzlich zu Polling verarbeitet die App Realtime-Events auf `public.boxes`
(INSERT/UPDATE). Erwartete Felder:

- `id` -> Boxnummer
- `status` -> State string
- `remaining_seconds` -> Countdown in Sekunden (optional)

## Error Code Values

- `invalid_signature`
- `box_unavailable`
- `reservation_expired`
- `session_not_active`
- `unknown`
