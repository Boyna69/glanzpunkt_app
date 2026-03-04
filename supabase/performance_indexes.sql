-- Performance indexes for wash flow and history endpoints.
-- Run once in Supabase SQL Editor (project owner).

begin;

create index if not exists idx_wash_sessions_user_started_at
  on public.wash_sessions (user_id, started_at desc);

create index if not exists idx_wash_sessions_box_ends_at
  on public.wash_sessions (box_id, ends_at);

create index if not exists idx_wash_sessions_ends_at
  on public.wash_sessions (ends_at);

create index if not exists idx_box_reservations_active_box
  on public.box_reservations (box_id, reserved_until)
  where consumed_at is null;

commit;
