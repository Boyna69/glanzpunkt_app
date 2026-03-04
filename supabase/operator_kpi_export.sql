-- KPI export RPC for operator/owner (day/week/month windows).
-- Run this in Supabase SQL Editor as project owner.
-- Requires: public.require_operator_or_owner() from rpc_wash_actions.sql

begin;

create or replace function public.kpi_export(period text default 'day')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period text := lower(coalesce(trim($1), 'day'));
  v_tz constant text := 'Europe/Berlin';
  v_now_utc timestamptz := now();
  v_now_local timestamp := timezone(v_tz, v_now_utc);
  v_window_start_local timestamp;
  v_window_start_utc timestamptz;
  v_window_end timestamptz := v_now_utc;
  v_stride interval;
  v_previous_window_start timestamptz;
  v_previous_window_end timestamptz;
  v_boxes_total integer := 0;
  v_boxes_available integer := 0;
  v_boxes_reserved integer := 0;
  v_boxes_active integer := 0;
  v_boxes_cleaning integer := 0;
  v_boxes_out_of_service integer := 0;
  v_active_sessions integer := 0;
  v_sessions_started integer := 0;
  v_wash_revenue_eur numeric := 0;
  v_top_up_revenue_eur numeric := 0;
  v_quick_fixes integer := 0;
  v_cleaning_actions integer := 0;
  v_open_reservations integer := 0;
  v_stale_reservations integer := 0;
  v_previous_sessions_started integer := 0;
  v_previous_wash_revenue_eur numeric := 0;
  v_previous_top_up_revenue_eur numeric := 0;
  v_delta_sessions_started integer := 0;
  v_delta_wash_revenue_eur numeric := 0;
  v_delta_top_up_revenue_eur numeric := 0;
  v_delta_sessions_started_pct numeric;
  v_delta_wash_revenue_pct numeric;
  v_delta_top_up_revenue_pct numeric;
begin
  perform public.require_operator_or_owner();

  if v_period = 'day' then
    v_window_start_local := date_trunc('day', v_now_local);
    v_stride := interval '1 day';
  elsif v_period = 'week' then
    -- PostgreSQL date_trunc('week') uses ISO week start (Monday).
    v_window_start_local := date_trunc('week', v_now_local);
    v_stride := interval '1 week';
  elsif v_period = 'month' then
    v_window_start_local := date_trunc('month', v_now_local);
    v_stride := interval '1 month';
  else
    raise exception 'invalid_period';
  end if;

  v_window_start_utc := v_window_start_local at time zone v_tz;
  v_previous_window_start := v_window_start_utc - v_stride;
  v_previous_window_end := v_window_end - v_stride;

  select
    count(*)::int,
    count(*) filter (where b.status = 'available')::int,
    count(*) filter (where b.status = 'reserved')::int,
    count(*) filter (where b.status = 'active')::int,
    count(*) filter (where b.status = 'cleaning')::int,
    count(*) filter (where b.status = 'out_of_service')::int
  into
    v_boxes_total,
    v_boxes_available,
    v_boxes_reserved,
    v_boxes_active,
    v_boxes_cleaning,
    v_boxes_out_of_service
  from public.boxes b;

  select count(*)::int
  into v_active_sessions
  from public.wash_sessions s
  where s.ends_at > v_now_utc;

  select count(*)::int
  into v_sessions_started
  from public.wash_sessions s
  where s.started_at >= v_window_start_utc
    and s.started_at <= v_window_end;

  select count(*)::int
  into v_previous_sessions_started
  from public.wash_sessions s
  where s.started_at >= v_previous_window_start
    and s.started_at <= v_previous_window_end;

  select coalesce(sum(s.amount), 0)::numeric
  into v_wash_revenue_eur
  from public.wash_sessions s
  where s.started_at >= v_window_start_utc
    and s.started_at <= v_window_end;

  select coalesce(sum(s.amount), 0)::numeric
  into v_previous_wash_revenue_eur
  from public.wash_sessions s
  where s.started_at >= v_previous_window_start
    and s.started_at <= v_previous_window_end;

  select coalesce(sum(t.amount), 0)::numeric
  into v_top_up_revenue_eur
  from public.transactions t
  where t.amount > 0
    and t.created_at >= v_window_start_utc
    and t.created_at <= v_window_end;

  select coalesce(sum(t.amount), 0)::numeric
  into v_previous_top_up_revenue_eur
  from public.transactions t
  where t.amount > 0
    and t.created_at >= v_previous_window_start
    and t.created_at <= v_previous_window_end;

  select count(*)::int
  into v_quick_fixes
  from public.operator_action_log l
  where l.action_name = 'quick_fix'
    and l.action_status in ('success', 'partial')
    and l.created_at >= v_window_start_utc
    and l.created_at <= v_window_end;

  select count(*)::int
  into v_cleaning_actions
  from public.operator_action_log l
  where l.action_name = 'mark_cleaned'
    and l.action_status = 'success'
    and l.created_at >= v_window_start_utc
    and l.created_at <= v_window_end;

  select count(*)::int
  into v_open_reservations
  from public.box_reservations r
  where r.consumed_at is null
    and r.reserved_until > v_now_utc;

  select count(*)::int
  into v_stale_reservations
  from public.box_reservations r
  where r.consumed_at is null
    and r.reserved_until <= v_now_utc;

  v_delta_sessions_started := v_sessions_started - v_previous_sessions_started;
  v_delta_wash_revenue_eur := v_wash_revenue_eur - v_previous_wash_revenue_eur;
  v_delta_top_up_revenue_eur := v_top_up_revenue_eur - v_previous_top_up_revenue_eur;

  if v_previous_sessions_started <> 0 then
    v_delta_sessions_started_pct :=
      ((v_delta_sessions_started::numeric / v_previous_sessions_started::numeric) * 100.0);
  else
    v_delta_sessions_started_pct := null;
  end if;

  if v_previous_wash_revenue_eur <> 0 then
    v_delta_wash_revenue_pct :=
      ((v_delta_wash_revenue_eur / v_previous_wash_revenue_eur) * 100.0);
  else
    v_delta_wash_revenue_pct := null;
  end if;

  if v_previous_top_up_revenue_eur <> 0 then
    v_delta_top_up_revenue_pct :=
      ((v_delta_top_up_revenue_eur / v_previous_top_up_revenue_eur) * 100.0);
  else
    v_delta_top_up_revenue_pct := null;
  end if;

  return jsonb_build_object(
    'period', v_period,
    'window_start', v_window_start_utc,
    'window_end', v_window_end,
    'previous_window_start', v_previous_window_start,
    'previous_window_end', v_previous_window_end,
    'generated_at', v_now_utc,
    'boxes_total', v_boxes_total,
    'boxes_available', v_boxes_available,
    'boxes_reserved', v_boxes_reserved,
    'boxes_active', v_boxes_active,
    'boxes_cleaning', v_boxes_cleaning,
    'boxes_out_of_service', v_boxes_out_of_service,
    'active_sessions', v_active_sessions,
    'sessions_started', v_sessions_started,
    'previous_sessions_started', v_previous_sessions_started,
    'delta_sessions_started', v_delta_sessions_started,
    'delta_sessions_started_pct', v_delta_sessions_started_pct,
    'wash_revenue_eur', v_wash_revenue_eur,
    'previous_wash_revenue_eur', v_previous_wash_revenue_eur,
    'delta_wash_revenue_eur', v_delta_wash_revenue_eur,
    'delta_wash_revenue_pct', v_delta_wash_revenue_pct,
    'top_up_revenue_eur', v_top_up_revenue_eur,
    'previous_top_up_revenue_eur', v_previous_top_up_revenue_eur,
    'delta_top_up_revenue_eur', v_delta_top_up_revenue_eur,
    'delta_top_up_revenue_pct', v_delta_top_up_revenue_pct,
    'quick_fixes', v_quick_fixes,
    'cleaning_actions', v_cleaning_actions,
    'open_reservations', v_open_reservations,
    'stale_reservations', v_stale_reservations
  );
end;
$$;

revoke all on function public.kpi_export(text) from public;
grant execute on function public.kpi_export(text) to authenticated;

commit;

notify pgrst, 'reload schema';
