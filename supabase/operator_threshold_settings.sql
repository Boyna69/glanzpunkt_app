-- Operator threshold settings (cleaning interval + long-active alert).
-- Run this in Supabase SQL Editor as project owner.
-- Requires: public.require_operator_or_owner() from rpc_wash_actions.sql

begin;

create table if not exists public.operator_threshold_settings (
  singleton boolean primary key default true check (singleton),
  cleaning_interval_washes integer not null default 75
    check (cleaning_interval_washes between 1 and 500),
  long_active_minutes integer not null default 20
    check (long_active_minutes between 1 and 240),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.operator_threshold_settings enable row level security;
revoke all on table public.operator_threshold_settings from public, anon, authenticated;

do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'operator_threshold_settings'
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      p.policyname,
      p.schemaname,
      p.tablename
    );
  end loop;
end $$;

create policy "operator_threshold_settings_select_operator_owner"
on public.operator_threshold_settings
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role in ('operator', 'owner')
  )
);

insert into public.operator_threshold_settings (singleton)
values (true)
on conflict (singleton) do nothing;

create or replace function public.get_operator_threshold_settings()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cleaning_interval_washes integer;
  v_long_active_minutes integer;
  v_updated_at timestamptz;
  v_updated_by uuid;
begin
  perform public.require_operator_or_owner();

  insert into public.operator_threshold_settings (singleton)
  values (true)
  on conflict (singleton) do nothing;

  select
    s.cleaning_interval_washes,
    s.long_active_minutes,
    s.updated_at,
    s.updated_by
  into
    v_cleaning_interval_washes,
    v_long_active_minutes,
    v_updated_at,
    v_updated_by
  from public.operator_threshold_settings s
  where s.singleton = true;

  return jsonb_build_object(
    'cleaning_interval_washes', v_cleaning_interval_washes,
    'long_active_minutes', v_long_active_minutes,
    'updated_at', v_updated_at,
    'updated_by', v_updated_by
  );
end;
$$;

create or replace function public.set_operator_threshold_settings(
  cleaning_interval_washes integer default null,
  long_active_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_previous_cleaning_interval_washes integer;
  v_previous_long_active_minutes integer;
  v_cleaning_interval_washes integer;
  v_long_active_minutes integer;
  v_updated_at timestamptz;
  v_updated_by uuid;
begin
  perform public.require_operator_or_owner();

  select p.role
    into v_role
  from public.profiles p
  where p.id = v_user_id;

  if coalesce(v_role, 'customer') <> 'owner' then
    raise exception 'forbidden_owner_required' using errcode = '42501';
  end if;

  insert into public.operator_threshold_settings (singleton)
  values (true)
  on conflict (singleton) do nothing;

  select
    s.cleaning_interval_washes,
    s.long_active_minutes,
    coalesce($1, s.cleaning_interval_washes),
    coalesce($2, s.long_active_minutes)
  into
    v_previous_cleaning_interval_washes,
    v_previous_long_active_minutes,
    v_cleaning_interval_washes,
    v_long_active_minutes
  from public.operator_threshold_settings s
  where s.singleton = true
  for update;

  if v_cleaning_interval_washes is null then
    v_cleaning_interval_washes := 75;
  end if;
  if v_long_active_minutes is null then
    v_long_active_minutes := 20;
  end if;

  if v_cleaning_interval_washes < 1 or v_cleaning_interval_washes > 500 then
    raise exception 'invalid_cleaning_interval_washes';
  end if;
  if v_long_active_minutes < 1 or v_long_active_minutes > 240 then
    raise exception 'invalid_long_active_minutes';
  end if;

  update public.operator_threshold_settings s
  set cleaning_interval_washes = v_cleaning_interval_washes,
      long_active_minutes = v_long_active_minutes,
      updated_at = now(),
      updated_by = v_user_id
  where s.singleton = true
  returning s.updated_at, s.updated_by
  into v_updated_at, v_updated_by;

  -- Optional server-side audit hook (if operator action log RPC is available).
  if to_regprocedure('public.log_operator_action(text,text,integer,jsonb,text)') is not null then
    perform public.log_operator_action(
      'update_thresholds',
      'success',
      null,
      jsonb_build_object(
        'beforeCleaningIntervalWashes', v_previous_cleaning_interval_washes,
        'beforeLongActiveMinutes', v_previous_long_active_minutes,
        'afterCleaningIntervalWashes', v_cleaning_interval_washes,
        'afterLongActiveMinutes', v_long_active_minutes
      ),
      'rpc'
    );
  end if;

  return jsonb_build_object(
    'cleaning_interval_washes', v_cleaning_interval_washes,
    'long_active_minutes', v_long_active_minutes,
    'updated_at', v_updated_at,
    'updated_by', v_updated_by
  );
end;
$$;

revoke all on function public.get_operator_threshold_settings() from public;
revoke all on function public.set_operator_threshold_settings(integer, integer) from public;

grant execute on function public.get_operator_threshold_settings() to authenticated;
grant execute on function public.set_operator_threshold_settings(integer, integer) to authenticated;

commit;

notify pgrst, 'reload schema';
