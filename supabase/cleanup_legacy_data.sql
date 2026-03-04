-- Cleanup helper for legacy test data.
-- Run once in Supabase SQL Editor as project owner.

begin;

create table if not exists public.wash_sessions_legacy_backup (
  like public.wash_sessions including all
);

-- Legacy backup must never be client-accessible via PostgREST.
alter table public.wash_sessions_legacy_backup enable row level security;
revoke all on table public.wash_sessions_legacy_backup from public;
revoke all on table public.wash_sessions_legacy_backup from anon, authenticated;

insert into public.wash_sessions_legacy_backup
select *
from public.wash_sessions
where box_id is null;

delete from public.wash_sessions
where box_id is null;

-- Keep reservations table compact by removing consumed/expired rows.
delete from public.box_reservations
where consumed_at is not null
   or reserved_until < now();

commit;
