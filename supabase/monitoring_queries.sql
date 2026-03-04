-- Operational monitoring queries for Glanzpunkt wash backend.

-- 1) Current box state overview
select status, count(*) as boxes
from public.boxes
group by status
order by status;

-- 2) Active sessions currently running
select count(*) as active_sessions
from public.wash_sessions
where ends_at > now();

-- 3) Sessions already expired by time (for reconciliation visibility)
select count(*) as expired_sessions
from public.wash_sessions
where ends_at <= now();

-- 4) Open reservations (not consumed, not expired)
select count(*) as open_reservations
from public.box_reservations
where consumed_at is null
  and reserved_until > now();

-- 5) Potentially stale reservations (not consumed, already expired)
select count(*) as stale_reservations
from public.box_reservations
where consumed_at is null
  and reserved_until <= now();

-- 6) Legacy/invalid session rows that should be cleaned up
select count(*) as sessions_with_null_box
from public.wash_sessions
where box_id is null;

-- 7) Last 20 sessions (audit view)
select id, user_id, box_id, amount, started_at, ends_at
from public.wash_sessions
order by started_at desc
limit 20;
