-- Loyalty + wallet hardening v2
-- Goal:
-- 1) Loyalty state is derived server-side from completed paid wash_sessions.
-- 2) Reward usage is derived from reward redemption transactions/sessions.
-- 3) Transaction rows get explicit kind values for reliable wallet typing.
--
-- Run this AFTER rpc_wash_actions.sql.

begin;

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

revoke all on function public.loyalty_derived_state(uuid) from public, anon, authenticated;

commit;
