-- Operator/Owner role administration.
-- Run in Supabase SQL Editor as project owner.

begin;

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

commit;

-- ----------------------------------------------------------------------------
-- Examples
-- ----------------------------------------------------------------------------
-- Promote one user to operator:
-- update public.profiles
-- set role = 'operator'
-- where id = '<SUPABASE_USER_UUID>';

-- Promote one user to owner:
-- update public.profiles
-- set role = 'owner'
-- where id = '<SUPABASE_USER_UUID>';

-- Demote to customer:
-- update public.profiles
-- set role = 'customer'
-- where id = '<SUPABASE_USER_UUID>';

-- Verify current roles:
-- select id, email, role
-- from public.profiles
-- order by email asc nulls last;
