-- Monitoring KPI extension: adds revenue/top-up fields to monitoring_snapshot().
-- Run this after rpc_wash_actions.sql.

begin;

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

revoke all on function public.monitoring_snapshot() from public;
grant execute on function public.monitoring_snapshot() to authenticated;

commit;

notify pgrst, 'reload schema';

