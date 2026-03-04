-- Harden boxes access:
-- - client can only SELECT
-- - only authenticated users can SELECT
-- - no direct INSERT/UPDATE/DELETE from client roles
-- - writes should happen via Edge Functions using service role

begin;

alter table if exists public.boxes enable row level security;

drop policy if exists "boxes_select_public" on public.boxes;
drop policy if exists "boxes_select_authenticated" on public.boxes;

create policy "boxes_select_authenticated"
on public.boxes
for select
to authenticated
using (true);

revoke all on table public.boxes from anon, authenticated;
grant select on table public.boxes to authenticated;

commit;

