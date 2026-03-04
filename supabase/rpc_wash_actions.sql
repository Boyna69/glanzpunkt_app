-- Wash actions as RPC layer (secure app-facing API).
-- Execute in Supabase SQL Editor after base tables and RLS exist.
--
-- Current schema assumptions:
--   boxes(id, status, remaining_seconds, updated_at)
--   wash_sessions(id, user_id, box_id, amount, started_at, ends_at)
--   profiles(id, balance)
--   transactions(id, user_id, amount, created_at)
--
-- Functions:
--   public.reserve(box_id)
--   public.cancel_reservation(box_id)
--   public.activate(box_id, amount)
--   public.activate_reward(box_id)
--   public.stop(session_id)
--   public.status(box_id)
--   public.recent_sessions(max_rows)
--   public.expire_active_sessions_internal()
--   public.expire_active_sessions()
--   public.top_up(amount)
--   public.loyalty_status()
--   public.record_purchase() -- deprecated no-op compatibility wrapper

begin;

create extension if not exists pgcrypto;

create table if not exists public.box_reservations (
  reservation_token text primary key default replace(gen_random_uuid()::text, '-', ''),
  box_id integer not null references public.boxes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reserved_until timestamptz not null,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);

create index if not exists idx_box_reservations_box_user
  on public.box_reservations (box_id, user_id);

alter table if exists public.box_reservations enable row level security;
revoke all on table public.box_reservations from public;
revoke all on table public.box_reservations from anon, authenticated;

create table if not exists public.loyalty_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  completed_purchases integer not null default 0
    check (completed_purchases >= 0),
  reward_slots integer not null default 0
    check (reward_slots >= 0),
  updated_at timestamptz not null default now()
);

alter table if exists public.loyalty_wallets enable row level security;
revoke all on table public.loyalty_wallets from public;
revoke all on table public.loyalty_wallets from anon, authenticated;

alter table if exists public.transactions
  add column if not exists kind text;

update public.transactions t
set kind = case
  when t.amount > 0 then 'top_up'
  when t.amount < 0 then 'wash_charge'
  when t.amount = 0 then 'reward_redeem'
  else 'unknown'
end
where t.kind is null;

create table if not exists public.ops_runtime_state (
  key text primary key,
  last_run_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table if exists public.ops_runtime_state enable row level security;
revoke all on table public.ops_runtime_state from public;
revoke all on table public.ops_runtime_state from anon, authenticated;

create or replace function public.require_operator_or_owner()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_role text;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select p.role
    into v_role
  from public.profiles p
  where p.id = v_user_id;

  if coalesce(v_role, 'customer') not in ('operator', 'owner') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.reserve(box_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_box_id integer := $1;
  v_user_id uuid := auth.uid();
  v_status text;
  v_reserved_until timestamptz := now() + interval '5 minutes';
  v_token text;
  v_existing_user uuid;
  v_existing_until timestamptz;
  v_existing_token text;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select b.status
    into v_status
  from public.boxes b
  where b.id = v_box_id
  for update;

  if not found then
    raise exception 'box_not_found';
  end if;

  -- Remove stale/consumed reservations for this box before checking availability.
  delete from public.box_reservations r
  where r.box_id = v_box_id
    and (r.consumed_at is not null or r.reserved_until <= now());

  -- If there is still an open reservation, only the same user can reuse it.
  select r.user_id, r.reserved_until, r.reservation_token
    into v_existing_user, v_existing_until, v_existing_token
  from public.box_reservations r
  where r.box_id = v_box_id
    and r.consumed_at is null
    and r.reserved_until > now()
  order by r.created_at desc
  limit 1
  for update;

  if found then
    if v_existing_user <> v_user_id then
      raise exception 'box_unavailable';
    end if;

    update public.boxes
      set status = 'reserved',
          remaining_seconds = 0,
          updated_at = now()
    where id = v_box_id;

    return jsonb_build_object(
      'box_id', v_box_id,
      'reservation_token', v_existing_token,
      'reserved_until', v_existing_until
    );
  end if;

  if v_status not in ('available', 'reserved') then
    raise exception 'box_unavailable';
  end if;

  insert into public.box_reservations (box_id, user_id, reserved_until)
  values (v_box_id, v_user_id, v_reserved_until)
  returning reservation_token into v_token;

  update public.boxes
    set status = 'reserved',
        remaining_seconds = 0,
        updated_at = now()
  where id = v_box_id;

  return jsonb_build_object(
    'box_id', v_box_id,
    'reservation_token', v_token,
    'reserved_until', v_reserved_until
  );
end;
$$;

create or replace function public.cancel_reservation(box_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_box_id integer := $1;
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_deleted integer := 0;
  v_released integer := 0;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  delete from public.box_reservations r
  where r.box_id = v_box_id
    and r.user_id = v_user_id
    and r.consumed_at is null
    and r.reserved_until > v_now;

  get diagnostics v_deleted = row_count;

  update public.boxes b
    set status = 'available',
        remaining_seconds = 0,
        updated_at = now()
  where b.id = v_box_id
    and not exists (
      select 1
      from public.wash_sessions s
      where s.box_id = b.id
        and s.ends_at > v_now
    )
    and not exists (
      select 1
      from public.box_reservations r
      where r.box_id = b.id
        and r.consumed_at is null
        and r.reserved_until > v_now
    );

  get diagnostics v_released = row_count;

  return jsonb_build_object(
    'box_id', v_box_id,
    'cancelled', v_deleted > 0,
    'state', case when v_released > 0 then 'available' else null end
  );
end;
$$;

create or replace function public.activate(box_id integer, amount integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_box_id integer := $1;
  v_amount integer := $2;
  v_user_id uuid := auth.uid();
  v_status text;
  v_runtime_seconds integer;
  v_session_id bigint;
  v_now timestamptz := now();
  v_ends_at timestamptz;
  v_balance numeric;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  v_runtime_seconds := v_amount * 120;
  v_ends_at := v_now + make_interval(secs => v_runtime_seconds);

  select b.status
    into v_status
  from public.boxes b
  where b.id = v_box_id
  for update;

  if not found then
    raise exception 'box_not_found';
  end if;

  if v_status not in ('reserved', 'available') then
    raise exception 'box_unavailable';
  end if;

  if v_status = 'reserved' then
    if not exists (
      select 1
      from public.box_reservations r
      where r.box_id = v_box_id
        and r.user_id = v_user_id
        and r.consumed_at is null
        and r.reserved_until > v_now
    ) then
      raise exception 'reservation_expired';
    end if;
  end if;

  select coalesce(p.balance, 0)
    into v_balance
  from public.profiles p
  where p.id = v_user_id
  for update;

  if coalesce(v_balance, 0) < v_amount then
    raise exception 'insufficient_balance';
  end if;

  update public.profiles
    set balance = coalesce(balance, 0) - v_amount
  where id = v_user_id;

  insert into public.transactions (user_id, amount, kind, created_at)
  values (v_user_id, -v_amount, 'wash_charge', v_now);

  insert into public.wash_sessions (user_id, box_id, amount, started_at, ends_at)
  values (v_user_id, v_box_id, v_amount, v_now, v_ends_at)
  returning id into v_session_id;

  update public.boxes
    set status = 'active',
        remaining_seconds = v_runtime_seconds,
        updated_at = now()
  where id = v_box_id;

  update public.box_reservations br
    set consumed_at = now()
  where br.box_id = v_box_id
    and br.user_id = v_user_id
    and br.consumed_at is null;

  return jsonb_build_object(
    'session_id', v_session_id,
    'runtime_seconds', v_runtime_seconds,
    'runtime_minutes', ceil(v_runtime_seconds::numeric / 60.0)::int
  );
end;
$$;

create or replace function public.top_up(amount integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount integer := $1;
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_balance numeric;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  update public.profiles p
    set balance = coalesce(p.balance, 0) + v_amount
  where p.id = v_user_id
  returning coalesce(p.balance, 0) into v_balance;

  if not found then
    raise exception 'profile_not_found';
  end if;

  insert into public.transactions (user_id, amount, kind, created_at)
  values (v_user_id, v_amount, 'top_up', v_now);

  return jsonb_build_object(
    'amount', v_amount,
    'balance', coalesce(v_balance, 0)
  );
end;
$$;

create or replace function public.stop(session_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_box_id integer;
  v_session_id bigint;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  begin
    v_session_id := trim(session_id)::bigint;
  exception when others then
    raise exception 'invalid_session_id';
  end;

  select s.box_id
    into v_box_id
  from public.wash_sessions s
  where s.id = v_session_id
    and s.user_id = v_user_id
    and s.ends_at > now()
  for update;

  if not found then
    raise exception 'session_not_active';
  end if;

  update public.wash_sessions
    set ends_at = now()
  where id = v_session_id
    and user_id = v_user_id;

  update public.boxes
    set status = 'available',
        remaining_seconds = 0,
        updated_at = now()
  where id = v_box_id;

  return jsonb_build_object(
    'session_id', v_session_id,
    'box_id', v_box_id,
    'state', 'available'
  );
end;
$$;

create or replace function public.status(box_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_remaining_seconds integer;
  v_now timestamptz := now();
  v_ends_at timestamptz;
  v_reserved_until timestamptz;
begin
  select b.status, b.remaining_seconds
    into v_status, v_remaining_seconds
  from public.boxes b
  where b.id = status.box_id
  for update;

  if not found then
    raise exception 'box_not_found';
  end if;

  delete from public.box_reservations r
  where r.box_id = status.box_id
    and r.consumed_at is null
    and r.reserved_until <= v_now;

  select s.ends_at
    into v_ends_at
  from public.wash_sessions s
  where s.box_id = status.box_id
    and s.ends_at > v_now
  order by s.ends_at desc
  limit 1;

  select r.reserved_until
    into v_reserved_until
  from public.box_reservations r
  where r.box_id = status.box_id
    and r.consumed_at is null
    and r.reserved_until > v_now
  order by r.reserved_until desc
  limit 1;

  if v_ends_at is not null then
    v_remaining_seconds := greatest(0, floor(extract(epoch from (v_ends_at - v_now)))::int);
    v_status := case when v_remaining_seconds > 0 then 'active' else 'available' end;
  elsif v_status in ('cleaning', 'out_of_service') then
    v_remaining_seconds := greatest(0, coalesce(v_remaining_seconds, 0));
  elsif v_reserved_until is not null then
    v_status := 'reserved';
    v_remaining_seconds := 0;
  else
    v_status := 'available';
    v_remaining_seconds := 0;
  end if;

  update public.boxes
    set status = v_status,
        remaining_seconds = v_remaining_seconds,
        updated_at = now()
  where id = status.box_id;

  return jsonb_build_object(
    'box_id', status.box_id,
    'state', v_status,
    'remaining_seconds', v_remaining_seconds
  );
end;
$$;

create or replace function public.expire_active_sessions_internal()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_last_run_at timestamptz;
  v_expired_count integer;
  v_expired_total integer;
  v_updated_boxes integer;
  v_expired_reservations integer;
  v_released_reserved_boxes integer;
begin
  insert into public.ops_runtime_state (key, last_run_at, updated_at)
  values ('expire_active_sessions', v_now - interval '1 minute', v_now)
  on conflict (key) do nothing;

  select s.last_run_at
    into v_last_run_at
  from public.ops_runtime_state s
  where s.key = 'expire_active_sessions'
  for update;

  if v_last_run_at is null then
    v_last_run_at := v_now - interval '1 minute';
  end if;

  select count(*)::int
    into v_expired_count
  from public.wash_sessions s
  where s.ends_at > v_last_run_at
    and s.ends_at <= v_now;

  select count(*)::int
    into v_expired_total
  from public.wash_sessions s
  where s.ends_at <= v_now;

  with expired_boxes as (
    select distinct s.box_id
    from public.wash_sessions s
    where s.ends_at <= v_now
  )
  update public.boxes b
    set status = 'available',
        remaining_seconds = 0,
        updated_at = now()
  from expired_boxes e
  where b.id = e.box_id
    and not exists (
      select 1
      from public.wash_sessions active
      where active.box_id = b.id
        and active.ends_at > v_now
    );

  get diagnostics v_updated_boxes = row_count;

  delete from public.box_reservations r
  where r.consumed_at is null
    and r.reserved_until <= v_now;

  get diagnostics v_expired_reservations = row_count;

  update public.boxes b
    set status = 'available',
        remaining_seconds = 0,
        updated_at = now()
  where b.status = 'reserved'
    and not exists (
      select 1
      from public.box_reservations r
      where r.box_id = b.id
        and r.consumed_at is null
        and r.reserved_until > v_now
    )
    and not exists (
      select 1
      from public.wash_sessions active
      where active.box_id = b.id
        and active.ends_at > v_now
    );

  get diagnostics v_released_reserved_boxes = row_count;

  update public.ops_runtime_state
    set last_run_at = v_now,
        updated_at = v_now
  where key = 'expire_active_sessions';

  return jsonb_build_object(
    'windowStart', v_last_run_at,
    'windowEnd', v_now,
    'expiredSessions', coalesce(v_expired_count, 0),
    'expiredSessionsTotalHistorical', coalesce(v_expired_total, 0),
    'updatedBoxes', coalesce(v_updated_boxes, 0),
    'expiredReservations', coalesce(v_expired_reservations, 0),
    'releasedReservedBoxes', coalesce(v_released_reserved_boxes, 0)
  );
end;
$$;

create or replace function public.expire_active_sessions()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_operator_or_owner();
  return public.expire_active_sessions_internal();
end;
$$;

create or replace function public.loyalty_derived_state(target_user_id uuid)
returns table (
  completed integer,
  reward_slots integer,
  goal integer,
  completed_total integer,
  rewards_earned_total integer,
  rewards_used_total integer
)
language sql
security definer
set search_path = public
as $$
  with paid as (
    select count(*)::int as paid_completed
    from public.wash_sessions s
    where s.user_id = target_user_id
      and coalesce(s.amount, 0) > 0
      and s.ends_at is not null
      and s.ends_at <= now()
  ),
  used as (
    select count(*)::int as rewards_used
    from public.transactions t
    where t.user_id = target_user_id
      and (
        coalesce(t.kind, '') = 'reward_redeem'
        or t.amount = 0
      )
  )
  select
    mod(p.paid_completed, 10)::int as completed,
    greatest((p.paid_completed / 10) - u.rewards_used, 0)::int as reward_slots,
    10::int as goal,
    p.paid_completed::int as completed_total,
    (p.paid_completed / 10)::int as rewards_earned_total,
    u.rewards_used::int as rewards_used_total
  from paid p
  cross join used u;
$$;

create or replace function public.loyalty_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_completed integer := 0;
  v_reward_slots integer := 0;
  v_goal integer := 10;
  v_completed_total integer := 0;
  v_rewards_earned_total integer := 0;
  v_rewards_used_total integer := 0;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select
    d.completed,
    d.reward_slots,
    d.goal,
    d.completed_total,
    d.rewards_earned_total,
    d.rewards_used_total
    into
      v_completed,
      v_reward_slots,
      v_goal,
      v_completed_total,
      v_rewards_earned_total,
      v_rewards_used_total
  from public.loyalty_derived_state(v_user_id) d;

  insert into public.loyalty_wallets (
    user_id,
    completed_purchases,
    reward_slots,
    updated_at
  )
  values (
    v_user_id,
    coalesce(v_completed, 0),
    coalesce(v_reward_slots, 0),
    v_now
  )
  on conflict (user_id) do update
    set completed_purchases = excluded.completed_purchases,
        reward_slots = excluded.reward_slots,
        updated_at = excluded.updated_at;

  return jsonb_build_object(
    'completed', coalesce(v_completed, 0),
    'reward_slots', coalesce(v_reward_slots, 0),
    'goal', coalesce(v_goal, 10),
    'completed_total', coalesce(v_completed_total, 0),
    'rewards_earned_total', coalesce(v_rewards_earned_total, 0),
    'rewards_used_total', coalesce(v_rewards_used_total, 0),
    'source', 'derived_from_sessions'
  );
end;
$$;

create or replace function public.record_purchase()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Legacy compatibility endpoint. Loyalty is now derived server-side from
  -- completed wash_sessions and reward redemptions.
  return public.loyalty_status();
end;
$$;

create or replace function public.activate_reward(box_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_box_id integer := $1;
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_status text;
  v_session_id bigint;
  v_runtime_seconds integer := 600;
  v_ends_at timestamptz := v_now + interval '10 minutes';
  v_completed integer := 0;
  v_reward_slots integer := 0;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_user_id::text));

  select b.status
    into v_status
  from public.boxes b
  where b.id = v_box_id
  for update;

  if not found then
    raise exception 'box_not_found';
  end if;

  delete from public.box_reservations r
  where r.box_id = v_box_id
    and (r.consumed_at is not null or r.reserved_until <= v_now);

  if v_status not in ('available', 'reserved') then
    raise exception 'box_unavailable';
  end if;

  if v_status = 'reserved' then
    if not exists (
      select 1
      from public.box_reservations r
      where r.box_id = v_box_id
        and r.user_id = v_user_id
        and r.consumed_at is null
        and r.reserved_until > v_now
    ) then
      raise exception 'reservation_expired';
    end if;
  end if;

  select d.completed, d.reward_slots
    into v_completed, v_reward_slots
  from public.loyalty_derived_state(v_user_id) d;

  if coalesce(v_reward_slots, 0) <= 0 then
    raise exception 'no_reward_available';
  end if;

  insert into public.transactions (user_id, amount, kind, created_at)
  values (v_user_id, 0, 'reward_redeem', v_now);

  insert into public.wash_sessions (user_id, box_id, amount, started_at, ends_at)
  values (v_user_id, v_box_id, 0, v_now, v_ends_at)
  returning id into v_session_id;

  update public.boxes
    set status = 'active',
        remaining_seconds = v_runtime_seconds,
        updated_at = now()
  where id = v_box_id;

  update public.box_reservations br
    set consumed_at = now()
  where br.box_id = v_box_id
    and br.user_id = v_user_id
    and br.consumed_at is null;

  perform public.loyalty_status();

  return jsonb_build_object(
    'session_id', v_session_id,
    'runtime_seconds', v_runtime_seconds,
    'runtime_minutes', ceil(v_runtime_seconds::numeric / 60.0)::int
  );
end;
$$;

create or replace function public.recent_sessions(max_rows integer default 30)
returns table (
  id bigint,
  box_id integer,
  amount integer,
  started_at timestamptz,
  ends_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    s.id,
    s.box_id,
    s.amount,
    s.started_at,
    s.ends_at
  from public.wash_sessions s
  where s.user_id = auth.uid()
  order by s.started_at desc
  limit greatest(1, least(coalesce(max_rows, 30), 100));
$$;

create or replace function public.monitoring_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reconcile_last_run_at timestamptz;
  v_expired_since_last_reconcile integer;
  v_total_boxes integer;
  v_available integer;
  v_reserved integer;
  v_active integer;
  v_cleaning integer;
  v_out_of_service integer;
  v_active_sessions integer;
  v_sessions_next_5m integer;
  v_open_reservations integer;
  v_stale_reservations integer;
  v_null_box_sessions integer;
  v_sessions_last_24h integer;
  v_wash_revenue_24h numeric;
  v_wash_revenue_today numeric;
  v_topup_24h numeric;
  v_topup_today numeric;
begin
  perform public.require_operator_or_owner();

  select s.last_run_at
    into v_reconcile_last_run_at
  from public.ops_runtime_state s
  where s.key = 'expire_active_sessions';

  if v_reconcile_last_run_at is null then
    v_expired_since_last_reconcile := 0;
  else
    select count(*)::int
      into v_expired_since_last_reconcile
    from public.wash_sessions s
    where s.ends_at > v_reconcile_last_run_at
      and s.ends_at <= v_now;
  end if;

  select
    count(*)::int,
    count(*) filter (where b.status = 'available')::int,
    count(*) filter (where b.status = 'reserved')::int,
    count(*) filter (where b.status = 'active')::int,
    count(*) filter (where b.status = 'cleaning')::int,
    count(*) filter (where b.status = 'out_of_service')::int
  into
    v_total_boxes,
    v_available,
    v_reserved,
    v_active,
    v_cleaning,
    v_out_of_service
  from public.boxes b;

  select count(*)::int
    into v_active_sessions
  from public.wash_sessions s
  where s.ends_at > v_now;

  select count(*)::int
    into v_sessions_next_5m
  from public.wash_sessions s
  where s.ends_at > v_now
    and s.ends_at <= v_now + interval '5 minutes';

  select count(*)::int
    into v_open_reservations
  from public.box_reservations r
  where r.consumed_at is null
    and r.reserved_until > v_now;

  select count(*)::int
    into v_stale_reservations
  from public.box_reservations r
  where r.consumed_at is null
    and r.reserved_until <= v_now;

  select count(*)::int
    into v_null_box_sessions
  from public.wash_sessions s
  where s.box_id is null;

  select count(*)::int
    into v_sessions_last_24h
  from public.wash_sessions s
  where s.started_at >= v_now - interval '24 hours';

  select coalesce(sum(abs(t.amount)::numeric), 0)
    into v_wash_revenue_24h
  from public.transactions t
  where t.created_at >= v_now - interval '24 hours'
    and t.amount < 0
    and (
      coalesce(t.kind, '') = 'wash_charge'
      or t.kind is null
    );

  select coalesce(sum(abs(t.amount)::numeric), 0)
    into v_wash_revenue_today
  from public.transactions t
  where t.created_at >= date_trunc('day', v_now)
    and t.amount < 0
    and (
      coalesce(t.kind, '') = 'wash_charge'
      or t.kind is null
    );

  select coalesce(sum(t.amount::numeric), 0)
    into v_topup_24h
  from public.transactions t
  where t.created_at >= v_now - interval '24 hours'
    and t.amount > 0
    and (
      coalesce(t.kind, '') = 'top_up'
      or t.kind is null
    );

  select coalesce(sum(t.amount::numeric), 0)
    into v_topup_today
  from public.transactions t
  where t.created_at >= date_trunc('day', v_now)
    and t.amount > 0
    and (
      coalesce(t.kind, '') = 'top_up'
      or t.kind is null
    );

  return jsonb_build_object(
    'timestamp', v_now,
    'reconcileLastRunAt', v_reconcile_last_run_at,
    'expiredSessionsSinceLastRun', coalesce(v_expired_since_last_reconcile, 0),
    'boxes', jsonb_build_object(
      'total', coalesce(v_total_boxes, 0),
      'available', coalesce(v_available, 0),
      'reserved', coalesce(v_reserved, 0),
      'active', coalesce(v_active, 0),
      'cleaning', coalesce(v_cleaning, 0),
      'out_of_service', coalesce(v_out_of_service, 0)
    ),
    'activeSessions', coalesce(v_active_sessions, 0),
    'sessionsNext5m', coalesce(v_sessions_next_5m, 0),
    'openReservations', coalesce(v_open_reservations, 0),
    'staleReservations', coalesce(v_stale_reservations, 0),
    'sessionsWithNullBox', coalesce(v_null_box_sessions, 0),
    'sessionsLast24h', coalesce(v_sessions_last_24h, 0),
    'washRevenue24hEur', coalesce(round(v_wash_revenue_24h, 2), 0),
    'washRevenueTodayEur', coalesce(round(v_wash_revenue_today, 2), 0),
    'topUp24hEur', coalesce(round(v_topup_24h, 2), 0),
    'topUpTodayEur', coalesce(round(v_topup_today, 2), 0)
  );
end;
$$;

revoke all on function public.reserve(integer) from public;
revoke all on function public.require_operator_or_owner() from public;
revoke all on function public.cancel_reservation(integer) from public;
revoke all on function public.activate(integer, integer) from public;
revoke all on function public.activate_reward(integer) from public;
revoke all on function public.stop(text) from public;
revoke all on function public.status(integer) from public;
revoke all on function public.expire_active_sessions_internal() from public, anon, authenticated;
revoke all on function public.expire_active_sessions() from public;
revoke all on function public.recent_sessions(integer) from public;
revoke all on function public.top_up(integer) from public;
revoke all on function public.loyalty_derived_state(uuid) from public, anon, authenticated;
revoke all on function public.loyalty_status() from public;
revoke all on function public.record_purchase() from public;
revoke all on function public.monitoring_snapshot() from public;

grant execute on function public.reserve(integer) to authenticated;
grant execute on function public.require_operator_or_owner() to authenticated;
grant execute on function public.cancel_reservation(integer) to authenticated;
grant execute on function public.activate(integer, integer) to authenticated;
grant execute on function public.activate_reward(integer) to authenticated;
grant execute on function public.stop(text) to authenticated;
grant execute on function public.status(integer) to authenticated;
grant execute on function public.expire_active_sessions() to authenticated;
grant execute on function public.recent_sessions(integer) to authenticated;
grant execute on function public.top_up(integer) to authenticated;
grant execute on function public.loyalty_status() to authenticated;
grant execute on function public.record_purchase() to authenticated;
grant execute on function public.monitoring_snapshot() to authenticated;

commit;
