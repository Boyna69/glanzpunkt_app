-- Glanzpunkt Supabase RLS baseline
-- Run this in Supabase SQL Editor (project: ucnvzrpcjkpaltuylvbv).
-- Goal: strict tenant isolation by auth.uid().

begin;

-- Ensure tables are protected by RLS
alter table if exists public.profiles enable row level security;
alter table if exists public.wash_sessions enable row level security;
alter table if exists public.transactions enable row level security;
alter table if exists public.boxes enable row level security;

-- Add role model for hard separation between customer/operator/owner.
alter table if exists public.profiles
  add column if not exists role text;

update public.profiles
set role = 'customer'
where role is null
   or role not in ('customer', 'operator', 'owner');

alter table if exists public.profiles
  alter column role set default 'customer';

alter table if exists public.profiles
  alter column role set not null;

alter table if exists public.profiles
  drop constraint if exists profiles_role_check;

alter table if exists public.profiles
  add constraint profiles_role_check
  check (role in ('customer', 'operator', 'owner'));

-- Drop existing policies to avoid accidental over-permissive overlaps.
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles', 'wash_sessions', 'transactions', 'boxes')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      p.policyname,
      p.schemaname,
      p.tablename
    );
  end loop;
end $$;

-- ---------------------------------
-- profiles: own row only
-- ---------------------------------
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (id = auth.uid());

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Optional hard deny for delete from app clients
revoke delete on table public.profiles from authenticated, anon;
revoke update(role) on table public.profiles from authenticated, anon;

-- Extra hardening: authenticated app users cannot escalate their own role.
create or replace function public.prevent_profile_role_self_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and old.role is distinct from new.role then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_profile_role_self_change on public.profiles;
create trigger trg_prevent_profile_role_self_change
before update on public.profiles
for each row
execute function public.prevent_profile_role_self_change();

revoke all on function public.prevent_profile_role_self_change() from public;

-- ---------------------------------
-- wash_sessions: own rows only
-- ---------------------------------
create policy "wash_sessions_select_own"
on public.wash_sessions
for select
to authenticated
using (user_id = auth.uid());

-- No direct insert/update/delete policy on wash_sessions from app clients.
-- Writes must happen through SECURITY DEFINER RPCs only.
revoke insert, update, delete on table public.wash_sessions from authenticated, anon;

-- ---------------------------------
-- transactions: own rows only
-- ---------------------------------
create policy "transactions_select_own"
on public.transactions
for select
to authenticated
using (user_id = auth.uid());

-- No direct insert/update/delete policy on transactions from app clients.
-- Writes must happen through SECURITY DEFINER RPCs only.
revoke insert, update, delete on table public.transactions from authenticated, anon;

-- ---------------------------------
-- boxes: authenticated read-only, no direct client writes
-- ---------------------------------
create policy "boxes_select_authenticated"
on public.boxes
for select
to authenticated
using (true);

revoke insert, update, delete on table public.boxes from authenticated, anon;
revoke select on table public.boxes from anon;
grant select on table public.boxes to authenticated;

-- Keep explicit table grants aligned with intended operations
grant select, insert, update on table public.profiles to authenticated;
grant select on table public.wash_sessions to authenticated;
grant select on table public.transactions to authenticated;

commit;
