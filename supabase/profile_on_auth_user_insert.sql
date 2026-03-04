-- Auto-create profile row when a new auth user is created.
-- Run in Supabase SQL Editor after table public.profiles exists.

begin;

-- Ensure role column exists before trigger/backfill writes role.
alter table if exists public.profiles
  add column if not exists role text;

update public.profiles
set role = 'customer'
where role is null;

alter table if exists public.profiles
  alter column role set default 'customer';

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'customer')
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_create_profile on auth.users;

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user_profile();

-- Optional backfill for users that already exist but have no profile row yet.
insert into public.profiles (id, email, role)
select u.id, u.email, 'customer'
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

commit;
